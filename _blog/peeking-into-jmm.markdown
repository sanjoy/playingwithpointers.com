---
layout: post
title:  "Peeking into the Java Memory Model"
redirect_from:
 - /peeking-into-jmm.html
keywords: "java memory model, java, proof, jvm, memory model, multi threaded"
needsMathJAX : True
date: 2014-3-5
---

This is brief brain-dump of my understanding of the JMM. Content-wise
this is a rather loose post, focusing more on intuition and less on
preciseness, but hopefully it doesn't have any fundamental
mistakes. One day, when I have a lot of free time, I will try to
formalize the JMM in Agda or Coq, but for now English will have to do.

# Memory Models

A memory model, in the most abstract sense, is a predicate on
execution traces of programs.  It differentiates between _valid_ and
_invalid_ execution traces by asserting invariants on the values
observed by memory reads.  I have assumed the readers have some
intuitive understand of what a memory model looks like.

It is immaterial whether it is the ultimately the (`javac`, JIT)
compiler that has to respect the memory model or the machine.  If a
certain property of the system keeps the compiler from performing a
specific reordering, it is the compiler's job to emit appropriate
barriers to prevent that reordering at the CPU level; and if it is
okay for the compiler to legally make a reordering, then it doesn't
matter what the CPU thinks -- the compiler may do the transform before
code emission.

The Java memory model can be roughly split into two distinct sections:
an axiomatic _contract_ between the VM and the programs running on top
of the VM, and an abstract, operational notion of a _well formed_
execution.

# The Contract

With a thread X trying to execute `A` followed by `B` and thread Y
trying to execute `C` followed by `D` (all these being reads and
writes, for simplicity's sake) what are the possible states of the
system once both the threads are done?  If the system is sequentially
consistent, then the system may be in a state reached by any of the
following execution traces: { `A` `B` `C` `D` }, { `A` `C` `B` `D` },
{ `A` `C` `D` `B` }, { `C` `A` `B` `D` }, { `C` `A` `D` `B` } or { `C`
`D` `A` `B` }.  More generally, in a sequentially consistent system,
the total set of observable events

  * [PropertySC 1] have a total order to them -- it is always possible
    to give a meaningful answer to the question "did X happen before Y"?

  * [PropertySC 2] respects the program order -- if `A` happens before
    `B` in the source, `A` will appear to execute before `B` in the
    final execution trace.

  * [PropertySC 3] are all atomic, and immediately visible to every
    thread.  Specifically, a read from `var` will always get the value
    written in the write to `var` immediately preceding `var` in the
    total order from [PropertySC 1].

Sequential consistency is nice because it allows us to stick with the
comfortable illusion that threads "execute" by interleaving their
instructions into one shared instruction stream.  This is far from the
truth in systems with true parallelism, though; and the illusion is
difficult to maintain without significant performance penalty.  The
Java Memory Model tries to give us conditional sequential consistency
-- it guarantees that a _correctly synchronized_ Java program will
behave _as if_ it were running on a sequentially consistent runtime.

Before proceeding further, we need to digress a little into the
mathematical concepts of partially ordered sets (posets) and totally
ordered sets.  Informally, a totally ordered is a set with a relation
(denoted by `⟜` below) that satisfies certain axioms.  You have `a ⟜
a` (reflexivity), `(a ⟜ b) ∧ (b ⟜ c) ⇒ a ⟜ c` (transitivity) and the
fact that two arbitrary elements are always ordered with respect to
each other (totality).  It also has "antisymmetry", but we won't use
that today.  A partially ordered set is a totally ordered set without
the totality axiom.  In other words, in a poset you may have "neither
`a` `⟜` `b` nor `b` `⟜` `a`" for some `a`s and `b`s.

All the actions (an action being an execution of a statement by a
thread) in a program form a poset with a relation called the
_happens-before_ relation.  The _happens-before_ relation, which we'll
denote with `↣`, is an abstract relation (it has nothing to do with
things actually happening before other things).

A _data race_ is defined as two conflicting accesses (accesses to the
same location, at least one being a write) that aren't ordered by `↣`.
If all possible sequentially consistent execution traces of a program
are free of data races, the program is _correctly
synchronized_. [Property`↣` 0]

Once we are able to compute the `↣` relation from an execution trace
(we haven't discussed how to do that yet), [Property`↣` 0] gives us a
straightforward (but tedious) way to check that a program is correctly
synchronized.  We enumerate all possible execution traces that are
sequentially consistent (i.e. the combined instruction stream is an
interleaving of the instruction streams of individual threads),
compute the `↣` relation on each of those traces, and check that for
all pairs of conflicting access `a` and `b`, either `a` `↣` `b` or `b`
`↣` `a`.  If we are able to show that all conflicting data accesses
are ordered by the `↣` relation in every possible sequentially
consistent execution trace, then the program is certified to be
correctly synchronized, and will actually run as if it were being run
on a sequentially consistent runtime.

From the programmers' perspective, all she needs to do is ensure that
conflicting data accesses are ordered by the `↣` relation (which we'll
define in a moment) somehow, and once that constraint is satisfied,
she can think about her program _as if_ it were running on a
sequentially consistently runtime.

To compute the `↣` relation on an execution trace, we compute two
other relations first.  Both those relations form totally ordered sets
with a subset of actions in the program.

The first one is the _program order_ (we'll denote this by `p⇝`) --
this is an intra-thread total order which orders actions inside a
single thread sequentially, as defined by the java language semantics.
So if a thread executes `{ A; B; C; D; }` then `A` `p⇝` `B`, `A` `p⇝`
`C`, `B` `p⇝` `C` etc.  This too is an abstract relation and has
little to do with the actual execution order of the statements: if
there are no observable consequences of reordering `B` and `C`, then
the runtime may do so.  `p⇝` does not order actions across threads, it
does not have an answer to the question "is `A` `p⇝` `B`" where `A`
and `B` are actions executed by two different threads.  So,
_globally_, `p⇝` is a partial order, but since it orders all
statements _within_ a thread, it is an _intra-thread_ total order.
`p⇝` isn't exactly a runtime artifact (modulo control dependency on
runtime inputs), we can determine it by statically analyzing a
program.

The second one is the _synchronization order_ (we'll denote this by
`so⇝`) -- this is a global (cross thread) total order on
"synchronization actions".  For our purposes at this time, these
"synchronization actions" are `volatile` reads and writes (there are
others mentioned in [^1], `monitorenter`s and `monitorexit`s are
equivalent to `volatile` reads and writes in this context, for
instance).  This means given two synchronization actions, `A` and `B`,
either `A` `so⇝` `B` or `B` `so⇝` `A`.  As an aside, this isn't true
with `↣` (which orders arbitrary actions) -- `↣` is partially ordered
and we may have (non synchronized) actions `C` and `D` where neither
`C` `↣` `D` nor `D` `↣` `C`.  `so⇝` respects `p⇝`, meaning if `X` and
`Y` are synchronization actions, then (`X` `p⇝` `Y` ) `⇒` (`X` `so⇝`
`Y`).  `so⇝` is a runtime artifact, even with fixed inputs, two
executions of a program may have different relations as `so⇝`.

`so⇝` is used to derive the "synchronized with" relation (denoted as
`sw⇝`).  `A` `sw⇝` `B` is a shorthand for "`B` is a `volatile` read of
a variable `var`" ∧ "`A` is a `volatile` write of the same variable
`var`" ∧ "`A` `so⇝` `B`".

`↣` is the transitive closure of the union of `sw⇝` and `p⇝`.  That is
just a fancy way of saying that

  * if `A` `p⇝` `B` then `A` `↣` `B`
  * if `A` `sw⇝` `B` then `A` `↣` `B`
  * if `A` `↣` `B`, `B` `↣` `C` then `A` `↣` `C`.

Now that we can compute `↣`, let us run through and "prove" an
example:

{% highlight java %}
volatile Task queue = null;

void ThreadA() {    
  Task t = new Task();
  t.name = "foo"; // normal store
  queue = t;      // volatile store (vS)
  // t.otherName = "bar";
}

void ThreadB() {    
  Task q = queue; // volatile load (vL)
  if (q != null) {
    String name = q.name;
    // String otherName = q.otherName;
    
    System.out.println(name);
    // System.out.println(otherName);
  }
}
{% endhighlight %}

We'll try to prove that `ThreadB` will either print nothing at all, or
`"foo"`.  If we can somehow show that this program is correctly
synchronized, then we'd be able to use [Property`↣` 0] and say that
this program will obey "as if" sequential semantics.  After that the
proof reduces to conditioning on "is `vL` before or after `vS` in the
total sequentially consistent order?".  To show that the program is
race free, we start with some sequentially consistent execution trace
`τ`.  Since `τ` is sequentially consistent, `vL` is either ordered
before (first case) or after (second case) `vS`.  By [PropertySC 3] we
know that this means that the `vL` will be `null` in the first case
and `t` in the second.

The first case is the easier one -- since `vL` sees `null`, the load
from `q.name` doesn't happen, and we don't print anything.  In the
second case:

<div>
\(\begin{aligned}
            &amp; \; \texttt{vS} \; \texttt{so⇝} \; \texttt{vL} &amp; \text{sequentially consistent trace} \\
\Rightarrow &amp; \; \texttt{vS} \; \texttt{sw⇝} \; \texttt{vL} &amp; \text{definition of sw⇝} \\
\Rightarrow &amp; \; \texttt{vS} \; \texttt{↣}   \; \texttt{vL} &amp; \text{definition of ↣ (P.0)}\\
\\
            &amp; \; \left[ \texttt{t.name = "foo"} \right] \; \texttt{p⇝} \; \texttt{vS} \\
\Rightarrow &amp; \; \left[ \texttt{t.name = "foo"} \right] \; \texttt{↣}  \; \texttt{vS} &amp; \text{definition of ↣} \\
\Rightarrow &amp; \; \left[ \texttt{t.name = "foo"} \right] \; \texttt{↣}  \; \texttt{vL} &amp; \text{(P.1)} \\
\\
\text{Similarly}\\
\\
            &amp; \; \texttt{vL} \; \texttt{p⇝} \; \left[ \texttt{String name = q.name} \right] &amp; \text{} \\
\Rightarrow &amp; \; \texttt{vL} \; \texttt{↣}  \; \left[ \texttt{String name = q.name} \right] &amp; \text{(P.2)} \\
\end{aligned}\)

</div>
<div>&nbsp;</div>

By transitivity of `↣`, P.1 and P.2,

<div>
\(\begin{aligned}
\left[ \texttt{t.name = "foo"} \right] \; \texttt{↣} \; \left[ \texttt{String name = q.name} \right] \; \text{(P.3)} &amp; \\
\end{aligned}\)

</div>
<div>&nbsp;</div>

From P.0, P.1, P.2 and P.3, we see that all possible conflicting data
accesses are ordered by `↣`.  This gives us as-if sequential
consistency via [Property`↣` 0], and a straightforward way to reason
about the output we can expect.

As an exercise, try to (formally) analyze the consequences of
uncommenting the lines touching the `otherName` field.

# Well Formed Executions

Now that the contract between the VM and the programmers has been
fixed, we need some way to discover the constraints the contract
places on VM authors.  For instance, one way to implement the contract
is to prevent all re-orderings by severely limiting compiler
optimizations and emitting hardware fences around all loads and
stores.  While that approach _may_ result in correct behavior, it is
clearly too conservative from the performance point of view.  We'd
like to allow _some_ reorderings (and "strange" behavior), and still
be able to maintain the contract -- ideally, our operational scheme
should give the programmer sequential consistency if and only if the
program is correctly synchronized.

The JMM spec tells us what a "well ordered" execution means, and this
can be proved [^2] to be (strictly more than) enough to provide the
conditional sequential consistency contract.

While the formal abstract operational specification is somewhat
convoluted (as usual, see [1]), informally they assert two important
things:

 *  executions are _happens-before consistent_: reads don't see writes
    that happen after (the inverse of `↣`) them, and they don't see
    writes that were blocked by another write -- `r` won't see `w` if
    `w` `↣` `w'` `∧` `w'` `↣` `r`.

The JMM spec includes an example to show that (1) isn't enough to
provide the sequential consistency guarantee:

{% highlight java %}
nonvolatile global int a = 0, b = 0;

ThreadA() {
  int aL = a;
  if (aL == 1) b = 1;
}

ThreadB() {
  int bL = b;
  if (bL == 1) a = 1;
}
{% endhighlight %}

No sequentially consistent execution trace of this program has a data
race, meaning that this program _is_ correctly synchronized, and
should have "as if" sequentially consistent semantics.  However, the
stores to `a`, `b` and the corresponding loads aren't ordered by `↣`,
and (1) doesn't place any guarantee on reads _not_ seeing writes that
it doesn't have the `↣` relation with.  In other words, like in a bad
time travel movie, in theory there is nothing stopping `aL` from
"seeing" the future write `a = 1`, setting `b = 1` which is then seen
by `ThreadB` which, in turn, sets `a` to `1`; with the net effective
result of the write `b = 1` having caused itself.  This is impossible
of course, since it flies against causality and basic physical laws,
but we'd like whatever abstract operational semantics we choose to
prevent such situations _a priori_ (all the while preserving
opportunities for interesting optimizations), and to not have to
analyze such situations on a case by case basis.

Moreover, Java is a "type safe" programming language -- certain kinds
of errors cannot arise in Java, even in a racy program.  For instance,
you could never load an element from a `String[]` and get an
`Integer`.  You also cannot have values appear out of "thin air":

{% highlight java %}
int /* non-volatile */ a;
int /* non-volatile */ b;

ThreadA() {
  int tmpa = a;
  b = tmp;
}

ThreadB() {
  int tmpb = b;
  a = tmp;
}
{% endhighlight %}

The above program has a data race.  By the rules specified so far, in
a happens-before consistent execution you could have `a` = `b` = `42`
by the end of the execution of the two threads; the value `42` somehow
materialized out of "thin air" (although we all know where it came
from).  This is similar to the previous example -- the value of `a`
written by `ThreadB` was somehow propagated by the value of `b`
written by `ThreadA` which was somehow propagated by the value of `a`
written by `ThreadB` -- a causality loop!

This brings us to the second operational axiom:

 *  execution proceeds in chunks, "comitting" actions in a way that
    the final commit results in the execution trace we're trying to
    validate.  Very loosely speaking, when we are at commit `i`, reads
    that are uncommitted or are in the `i`th commit always see the
    write that preceded them in the happens before relation (this is
    subtly different from (1)).

In the above example, (2) prevents the causal loop that (1) allowed.
Specifically, as the load from `a` gets committed, it _has_ to see the
write dictated `↣`, which points (by an axiom I skipped for brevity)
to the initializer for `a`, which writes `0` to `a`.  `ThreadA` thus
takes the correct control flow and Java doesn't end up breaking
physics.

# Conclusions

I find the first part of the JMM vastly easier to grok than the second
part (that aims to avoid causality loops).  I have a hunch that
defining and avoiding causality loops in terms of fixed points will
make for a much cleaner set of axioms.

[^1]: <http://docs.oracle.com/javase/specs/jls/se7/html/jls-17.html#jls-17.4>
[^2]: <http://homepages.inf.ed.ac.uk/da/papers/drfformalization/>
