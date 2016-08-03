---
layout: post
title:  "Java Optimizations and the JMM"
permalink: optimizations-and-the-jmm.html
keywords: "optimizations, java memory model, jvm, virtual machine, proof"
needsMathJAX: True
---

The Java Memory Model is a predicate on execution traces[^trace] of
multi-threaded Java programs.  It gives meaning to programs using
Java's concurrency facilities, and (hence) constraints transformations
that may be performed on the program by the program's execution
environment.  The _execution environment_ (a non-standard term I just
made up) typically includes `javac` and the JVM the generated
bytecodes execute on, but in theory could involve other tools
depending on the toolchain.  For example, if you post-process the
generated `.class` files using some bytecode level tool, that tool
needs to understand and respect the JMM if it wants to make semantic
preserving transformations.

[^trace]: An execution trace is a tuple consisting of sets and
    relations on those sets.  See section 17.4.6 in the "Java Language
    Specification" for a precise definition.

My interest in the Java Memory Model stems from working on JIT
compilers for a JVM[^nomem].  JIT compilers too are a part of the
_execution environment_ as defined above, and can optimize programs
only in ways allowed by the JMM specification.  People much smarter
than me have come up with ways to safely (but conservatively) compile
standard Java concurrency primitives[^cookbook], but it is a nice
exercise to try to prove legality (or illegality, in case of this
post) of certain transforms from scratch.  This blog post tries to
show how some re-orderings (that may be done in as part of optimizing
a Java program for performance) that intuitively seem illegal are, in
fact, illegal, by deriving that illegality from directly the JMM spec.
I've assumed passing familiarity with the Java Memory Model, but I've
also tried to give references to the actual memory model specification
wherever appropriate.

[^cookbook]: See the [The JSR-133 Cookbook for Compiler Writers](http://gee.cs.oswego.edu/dl/jmm/cookbook.html) by Doug Lea et. al.

[^jvmls]: See "The Java Language Specification"

[^nomem]: Unfortunately, unlike Java the programming language, Java
    bytecodes don't have a defined memory model.  In practice this
    isn't a problem since the bytecodes closely follow constructs
    present in the Java programming language, and hence have a default
    "inherited" memory model.

# A Correctly Synchronized Example

Assume we've declared a class `Tuple`

{% highlight java %}
class Tuple {
  public int /* non-volatile */ nonVolatileField;
  public int volatile volatileField;
}
{% endhighlight %}

Now consider the following snippet in Java (we'll call this the
_pre-transform snippet_):

{% highlight java %}
void reader(Tuple tuple) {
  int regNV = 0;
  int regV = tuple.volatileF;
  if (regV == 1) { regNV = tuple.nonVolatileF; }
  // computation that uses both of the above
}
{% endhighlight %}

Can the above be transformed to the following (that we will call the
_post-transform_ snippet)?

{% highlight java %}
void reader(Tuple tuple) {
  int regNV = 0;
  int cache = tuple.nonVolatileF;
  int regV = tuple.volatileF;
  if (regV == 1) { regNV = cache; }
  // computation that uses both of the above
}
{% endhighlight %}

Giving a precise answer involves examining the complete Java program
-- depending on the context in which this snippet executes, the
transformed snippet may or may not be equivalent to the original.  For
example, if there are no writes to `volatileF` (and so `regV` is
always `0` and so is `regNV`) in the Java program then the transform
is trivially safe.  However, it is more interesting to be able to make
local judgments when JIT compiling a single method.  Specifically,
we'd like to know if a certain transformation is legal (or not) in
_all_ contexts because if it is, we can make the transformation
without probing the rest of the environment at all[^tractable].  It
follows that we can prove a transform illegal (in this restricted
sense of illegal) by giving a _context_ that acts as a counterexample
-- the existence of one context in which the pre-transform Java
snippet and the post-transform Java snippet behave in incompatible
ways is enough to make the transform unsafe to do locally, without
global analysis.

[^tractable]: In general it isn't even _possible_ to make global
    statements about a program that stay correct throughout the
    program lifetime because Java bytecodes are allowed to load
    arbitrary Java classes at run-time.  So even if some forms of such
    global analysis may be feasible from a computational perspective,
    predicates computed by such global analyses will not stay correct
    throughout the lifetime of the program.  There is a standard
    solution for such issues though: you register _dependencies_ on
    bits of compiled code that records the falsifiable assumptions
    made during the compilation and when any of these assumptions are
    violated, the associated blobs of code are thrown away.  Of
    course, the more aggressive you are in making falsifiable
    assumptions the more frequently you'll have to throw away compiled
    code, so there is a natural trade-off here.

If you're familiar with the Java Memory Model, you'd probably guess
that the transform above is *not* legal.  We'll show this by choosing
a global context in which the pre-transform snippet guarantees
something that the post-transform snippet doesn't.

Let's say that there is some other thread running `writer`, making the
full program:

{% highlight java %}
void writer(Tuple tuple) {
  tuple.nonVolatileF = 5;
  tuple.volatileF = 1;
}
void reader(Tuple tuple) {
  int regNV = 0;
  int regV = tuple.volatileF;
  if (regV == 1) { regNV = tuple.nonVolatileF; }
  // computation that uses both of the above
}
{% endhighlight %}

`reader` and `writer` are being called on the same `Tuple` object
that was allocated at program startup.

It is easy to show that all _sequentially consistent_ execution traces
of this program are _race free_, and hence the program as such is
_correctly synchronized_ (all these terms have very specific meanings,
see 17.4.5 [^jvmls]).  Correctly synchronized programs behave as if
they were executing on a sequentially consistent runtime[^seqcst], so
every execution of this program will look like an interleaving of
actions performed by each of the individual threads (including
non-volatile reads and writes).  Given that, we can show that `regV ==
1` implies `regNV == 5`.

[^seqcst]: Interestingly, this isn't an axiom (even though we state as
    such).  Any Java runtime providing _happens before consistency_
    and _well-ordered executions_ automatically provides the "if
    correctly synchronized then sequentially consistent" invariant.
    For a proof see ["The Java Memory Model", POPL
    '05](http://rsim.cs.illinois.edu/Pubs/popl05.pdf "PDF").

Now let us put the post-transform Java snippet in the same context.

{% highlight java %}
void writer(Tuple tuple) {
  tuple.nonVolatileF = 5;
  tuple.volatileF = 1;
}
void reader(Tuple tuple) {
  int regNV = 0;
  int cache = tuple.nonVolatileF;
  int regV = tuple.volatileF;
  if (regV == 1) { regNV = cache; }
  // computation that uses both of the above
}
{% endhighlight %}

Note that this is no longer _correctly synchronized_ and hence the
above reasoning doesn't follow directly.  To show that the assertion
"`regV == 1` implies `regNV == 5`" no longer holds, we will
demonstrate a legal execution that results in `regV == 1` and `regNV
== 0`:

Let $$E$$ be an execution (see 17.4.6[^jvmls]) with obvious $$P$$,
$$A$$, $$po$$, $$V$$; $$so$$ = $$so'$$ $$\cup$$ $$($$ `tuple.volatileF
= 1`, `int regV = tuple.volatileF` $$)$$ for some $$so'$$ [^1]; $$W$$
such that `regV` is `1` and `cache` is `0`; and computed $$sw$$ and
$$hb$$ (their values are functions of the other parameters of the
execution).  Something to note about $$sw$$: "(17.4.4[^jvmls]) The
write of the default value (zero, false, or null) to each variable
synchronizes-with the first action in every thread."

<a name="commit-sequence"></a>

We now need a set of _committing actions_ (17.4.8[^jvmls]) culminating
in the execution $$E$$.  Fortunately this is simpler than it sounds,
let:

[^1]: This notation is just a fancy way of saying `tuple.volatileF =
    1` is before `int regV = tuple.volatileF` in $$so$$ and I don't
    care about the remaining part of the relation.  Also, there is
    something worth noting here -- volatile reads and writes have a
    total order to them, and given that `regV` is `1`, there can be
    only one way `tuple.volatileF = 1` relates to `int regV =
    tuple.volatileF` in $$so$$.

  * $$C_0$$ is $$\emptyset$$ (by definition)

  * $$C_1$$ includes everything up to the point the two threads
    started.  I'm hand-waving here -- in general you won't be able to
    compress the entire sequence of actions leading up to the thread
    launch state into one commit.  But I don't think that restriction
    affects this proof.

  * $$C_2$$ is $$C_1$$ $$\cup$$ $$\{$$ `tuple.nonVolatileF = 5`,
    `tuple.volatileF = 1` $$\}$$

  * $$C_3$$ is $$C_2$$ $$\cup$$ $$\{$$ `int cache =
    tuple.nonVolatileF`, `int regV = tuple.volatileF` $$\}$$

  * $$C_4$$ is $$C_3$$ $$\cup$$ all thread finalization logic (the
    conditional assignment to the local variable `regNV`, calls to
    `join()`, the exit sequence deployed by `main` etc.).  $$C_4$$ too
    is hand-wavy, and in the same sense as $$C_1$$.

From this we create $$E_i$$ with $$E = E_4$$ such that $$A_i = C_i$$.
We now need to show that the reads in $$C_3$$ can see the write $$W$$
thinks they should.  The specification allows "freshly committed
reads" (i.e. reads in $$A_i$$ that aren't in $$C_{i - 1}$$) to see
writes in the execution they're introduced in ($$E_i$$) that are
different from what they see in the final execution but we won't need
to exploit that allowance here[^seepopl].

[^seepopl]: For an example that actually uses that clause, see section
    6 in ["The Java Memory Model", POPL
    '05](http://rsim.cs.illinois.edu/Pubs/popl05.pdf "PDF")

From JMM section 17.4.8[^jvmls]: "All reads in $$E_i$$ that are not in
$$C_{i-1}$$ must see writes that happen-before them. Each read $$r$$
in $$C_{i} - C_{i-1}$$ must see writes in $$C_{i-1}$$ in both $$E_i$$
and $$E$$, but may see a different write in $$E_i$$ from the one it
sees in $$E$$." and section 17.4.5[^jvmls]: "The default
initialization of any object _happens-before_ any other actions (other
than default-writes) of a program." give us that it is legal for `int
cache = tuple.nonVolatileF` to see the initial write to `nonVolatileF`
of its default value (`0`) that _happens-before_ it (and everything
else), and `int regV = tuple.volatileF` to see the write
`tuple.volatileF = 1` that also _happens-before_ it (since
`tuple.volatileF = 1` is before `int regV = tuple.volatileF` in the
_synchronization order_, and hence they have a _happens-before_
relationship via the _synchronizes with_ relationship).  Since none of
these judgments break _happens-before consistency_, we've thus
justified $$E$$, and hence proved that `regV == 1` and `regNV == 0` is
a legal result.

## Exercise

Find a series of committing actions that end with `regV` as `1` and
`cache` as `5` in this second example.

# A Racy Example

The first example had an interesting property -- the _pre-transform_
program was _correctly synchronized_ while the _post-transform_
program wasn't.  Let's try an example where the _pre-transform_
program isn't _correctly synchronized_ either.  Is it legal to
transform

{% highlight java %}
void reader(Tuple tuple) {
  int regV = tuple.volatileF;
  int regNV = tuple.nonVolatileF;
  // computation that uses both of the above
}
{% endhighlight %}

to the following?

{% highlight java %}
void reader(Tuple tuple) {
  int regNV = tuple.nonVolatileF;
  int regV = tuple.volatileF;
  // computation that uses both of the above
}
{% endhighlight %}

Like in the previous case, the real, precise answer depends on the
global context in which the snippets are being evaluated for
equivalence.  But we can still try to answer the question in terms of
the stronger notion of "equivalent in every context".

We build a set-up similar to what we used last time, and also use the
same guarantee (or invariant) -- that `regV == 1` implies `regNV == 5`
to differentiate the pre-transform and the post-transform programs:

{% highlight java %}
void writer(Tuple tuple) {
  tuple.nonVolatileF = 5;
  tuple.volatileF = 1;
}
void reader(Tuple tuple) {
  int regV = tuple.volatileF;
  int regNV = tuple.nonVolatileF;
  // computation that uses both of the above
}
{% endhighlight %}

Observe that there is a race here[^2] so the earlier logic that
exploited "as-if" sequentially consistency semantics will not directly
work.  However, _happens-before consistency_ is enough to give us what
we need.

[^2]: If you pick a sequentially consistent execution where `int regV
    = tuple.volatileF` is before `tuple.volatileF = 1` in the
    _synchronization order_, then the pair of conflicting access
    (17.4.5[^jvmls]) `tuple.nonVolatileF = 5` and `int regNV =
    tuple.nonVolatileF` are not ordered in _happens-before_.

"(17.4.5[^jvmls]) A set of actions $$A$$ is _happens-before
consistent_ if for all reads $$r$$ in $$A$$, where $$W(r)$$ is the
write action seen by $$r$$, it is not the case that either $$hb(r,
W(r))$$ or that there exists a write $$w$$ in $$A$$ such that $$w.v =
r.v$$ and $$hb(W(r), w)$$ and $$hb(w, r)$$."

In plain English, this says the following two things:

 1. A read cannot see a write that it happened before
 2. A write overrides other writes to the same memory location that
    happened before it (in terms of the _happens before_ relation) --
    a read cannot observe a write that happened before a write that
    happened before it (i.e. is two or more steps away on the _happens
    before_ relation).

We can use (2) to prove the required guarantee -- given that `regV` is
`1`, we know (since volatile loads and stores have a total order) that
`tuple.volatileF = 1` _happens before_ `int regV = tuple.volatileF`.
This means (by _program order_ and transitivity) `tuple.nonVolatileF =
5` _happens before_ `int regNV = tuple.nonVolatileF`.  The only other
write to `nonVolatileF` in the system, the write of the default
value[^defvalue] (`0` in this case), happens before
`tuple.nonVolatileF = 5` so by (2) above, `int regNV =
tuple.nonVolatileF` cannot see it.  In the language of the JMM, we
have `int regNV = tuple.nonVolatileF` as $$r$$, the initial write of
`0` to `tuple.nonVolatileF` as $$W(r)$$ and `tuple.nonVolatileF = 5`
as $$w$$.  By 17.4.5[^jvmls], $$r$$ cannot observe $$W(r)$$.

[^defvalue]: Also mentioned earlier, "(17.4.4[^jvmls]) The write of
     the default value (zero, false, or null) to each variable
     synchronizes-with the first action in every thread."

The _post-transform_ snippet in the same context looks like

{% highlight java %}
void writer(Tuple tuple) {
  tuple.nonVolatileF = 5;
  tuple.volatileF = 1;
}
void reader(Tuple tuple) {
  int regNV = tuple.nonVolatileF;
  int regV = tuple.volatileF;
  // computation that uses both of the above
}
{% endhighlight %}

We'll again try to show the legality of an execution that results in
`regNV == 0` with `regV == 1`.  Reasoning about this is very similar
to reasoning about the previous case, and we can use the [same commit
sequence](#commit-sequence) (modulo changing $$C_4$$ in obvious ways,
since we don't have a local variable involved here) to show legality
of an execution that ends with `regNV == 0` and `regV == 1`.

## Exercise

Using similar techniques, show that you cannot optimize (the proof
will have the same structure as the second example):

{% highlight java %}
void reader(Tuple tuple) {
  int regNV_a = tuple.nonVolatileField;
  int revV = tuple.volatileField;
  int regNV_b = tuple.nonVolatileField;
  // computation that uses all of the three above
}
{% endhighlight %}

to

{% highlight java %}
void reader(Tuple tuple) {
  int regNV_a = tuple.nonVolatileField;
  int regV = tuple.volatileField;
  int regNV_b = localNV_a;
  // computation that uses all of the three above
}
{% endhighlight %}
.

# Conclusion and Future Posts

There are several aspects of the Java Memory Model specification that
I'm confused about:

  *  What does the JSR-133 Cookbook do to prevent values from
     appearing of "thin-air"?  Does the cookbook by itself prevent
     problematic causality loops?

  *  There are several interesting and well-known categories of
     optimizations that are allegedly prevented by the memory model.
     What are those optimizations, what is the impact of this
     restriction?  Is there a clean subset of compiler optimizations
     that _are_ allowed?  This is more of a reading project -- several
     papers have been published on this topic.

It will be interesting to see how my understanding of the JMM evolves
over time.  I think I've _sort of_ started to see the big picture, but
there is still a long way to go.
