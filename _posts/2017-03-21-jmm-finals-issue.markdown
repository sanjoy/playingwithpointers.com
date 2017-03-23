---
layout: post
title:  "An issue with Java's final fields"
permalink: jmm-finals-issue.html
keywords: ""
needsMathJAX: True
---

I believe the current specification of final fields in the Java Memory
Model that is broken in one of the following ways:

 - It prevents some basic CSE-type compiler-optimizations
 - It requires the JVM to make every load an acquire load
 - It complicates compiler IR by forcing it to track syntactic
   dependencies
 - It requires weakening the JMM in a backward incompatible way

While this isn't exactly news (I have been told that the wording
around final fields in the JMM is known to be problematic), I could
not easily find an explicit record of this issue anywhere else on the
internet.  Hence this blog post.

## The Setting

Consider the following program:

{% highlight java %}
class Basic {
  int field;
  static Basic b = new Basic();
}

class WithFinalField {
  WithFinalField() {
    Basic rBasic = Basic.b;
    rBasic.field = 42;   // W0
    finalField = rBasic; // W1
  }

  final Basic finalField;
}

class Test {
  // Assume that there is some other thread that, at some point, constructs
  // an instance of WithFinalField and writes it to globalLocation.  Let that
  // write to globalLocation be W2.
  static WithFinalField globalLocation;

  public int test() {
    WithFinalField rWFF = Test.globalLocation;  // R0
    if (rWFF == null)
      return 42;

    Basic rBasicOld = Basic.b;
    Basic rBasic = rWFF.finalField;  // R1
    if (rBasicOld == rBasic)
      return rBasic.field;  // R2
    return 42;
  }
}
{% endhighlight java %}

My claim is that `Test.test` is guaranteed to return `42`.  (If you
believe this already, you can skip over to the "The problem".)

Informally, this follows from the "It will also see versions of any
object or array referenced by those final fields that are at least as
up-to-date as the final fields are." line in [The Java® Language
Specification, Section
17.5](https://docs.oracle.com/javase/specs/jls/se7/html/jls-17.html#jls-17.5).

Formally[^glitch], we have (I've contracted $$dereferences$$ to
$$dr$$):

[^glitch]: I've interpreted the section for Dereference Chain as "
    ... that sees the address of o such that dereferences(r, a)", not
    as "... r dereferences(r, a)".  I'm not sure what "r
    dereferences(r, a)" would even mean.

<div>
\(\begin{aligned}
            &amp; \; hb(\texttt{W0},\texttt{W1}) &amp; \text{program order} \\
            &amp; \; hb(\texttt{W1},\texttt{freeze}) &amp; \text{program order} \\
            &amp; \; hb(\texttt{W0},\texttt{freeze}) &amp; \text{transitivity} &amp; \qquad ... \; (0)\\
            &amp; \; hb(\texttt{freeze},\texttt{W2}) &amp; \text{program order} &amp; \qquad ... \; (1)\\
            &amp; \; mc(\texttt{W2},\texttt{R0}) &amp; \text{reads from} &amp; \qquad ... \; (2)\\
            &amp; \; dr(\texttt{R0},\texttt{R1}) &amp; \text{by definition} \\
            &amp; \; mc(\texttt{R0},\texttt{R1}) &amp; \text{from previous} \\
            &amp; \; dr(\texttt{R1},\texttt{R2}) &amp; \text{by definition} \\
            &amp; \; mc(\texttt{R1},\texttt{R2}) &amp; \text{from previous} \\
            &amp; \; dr(\texttt{R0},\texttt{R2}) &amp; \text{dr is a partial order} &amp; \qquad ... \; (3)\\
\end{aligned}\)
</div>
<div>&nbsp;</div>

By (0) (1), (2) and (3) we have $$hb(\texttt{W0}, \texttt{f})$$,
$$hb(\texttt{f}, \texttt{W2})$$, $$mc(\texttt{W2}, \texttt{R0})$$,
$$dr(\texttt{R0}, \texttt{R2})$$ implying "when determining which
values can be seen by `R2`, we consider $$hb(\texttt{W0},
\texttt{R2})$$".

Since the only other write to `rBasic.field` is the initialization
write of `0`, and that write happens-before `W0`; the only legal write
`R2` can observe is `W0`.  This means `R2` must return `42`.

## The Problem

If we do a context sensitive optimization, and change

{% highlight java %}
if (rBasicOld == rBasic)
  return rBasic.field;
{% endhighlight java %}

to

{% highlight java %}
if (rBasicOld == rBasic)
  return rBasicOld.field;
{% endhighlight java %}

then the invariant guaranteed by the JMM, that test always returns
`42`, no longer holds.

Formally it does not hold because you no longer have $$dr(\texttt{R1},
\texttt{R2})$$, and hence don't have $$dr(\texttt{R0}, \texttt{R2})$$.

Informally, it does not hold because after the above transform, you
can "reorder" the load from `rBasicOld` to before `R0`, which allows
observing a `0` for `rBasicOld.field` while observing a non-null value
for `rWFF`.  Alternatively, the load from `rBasicOld` could get CSE'ed
with an earlier load from `rBasicOld` with the same consequences.

I used a static location for simplicity here, but `Basic.b`
(i.e. `rBasicOld`) could have been any shared value accessible to the
constructor and `Test.test`.

If we're okay weakening the JMM, we can maybe fix this by saying that
the transitive visibility rules only apply to newly constructed
objects that have not escaped.  That is, not only does the object with
final fields have to be unescaped at the point of the freeze action,
but any referents reachable via final fields also need to be unescaped
at that point.

However, that is a backward incompatible change as far as I can tell,
since we'd be providing looser guarantees than we do now.
