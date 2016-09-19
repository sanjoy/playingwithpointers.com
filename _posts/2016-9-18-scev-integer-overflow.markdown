---
layout: post
title:  "Integer overflow in LLVM's ScalarEvolution"
permalink: scev-integer-overflow.html
keywords: "LLVM, scalar evolution, SCEV"
---

*This is a short note on how integer overflow fits in with LLVM's
ScalarEvolution.  This post is specific to LLVM's implementation of
ScalarEvolution, and I've assumed some familiarity with LLVM internals
and integer arithmetic.*

# ScalarEvolution and add recurrences

ScalarEvolution is an analysis in LLVM[^scevextra] that helps its
clients reason about induction variables.  It does this by
mapping[^lazy] SSA values into objects of a `SCEV` type, and
implementing an algebra on top of it.  Using this algebra, clients of
ScalarEvolution can ask questions like "is `A` always signed-less-than
`B`?" or "is the difference between `A` and `B` a constant integer?",
where `A` and `B` are objects of the `SCEV` data type.

[^scevextra]: I should point that GCC has a [ScalarEvolution
    framework](https://github.com/gcc-mirror/gcc/blob/master/gcc/tree-scalar-evolution.c)
    too (actually I'm fairly sure that LLVM followed GCC here).
    However, all of this post is only about LLVM's implementation of
    ScalarEvolution, since that is what I am familiar with; and an
    unqualified reference to "ScalarEvolution" should be taken to
    imply "LLVM's implementation of ScalarEvolution".

[^lazy]: There is some laziness and caching involved, but that's just
    an implementation detail.

As an algebraic data type, `SCEV` can be expressed as (in a
Haskell-like syntax):

    data SCEV = SCEVConstant ConstantInt
              | SCEVUnknown SSAValue
              | SCEVTruncate SCEV | SCEVZeroExtend SCEV | SCEVSignExtend SCEV
              | SCEVAdd SCEV | SCEVMul SCEV | SCEVUDiv SCEV
              | SCEVSMax SCEV SCEV | SCEVUMax SCEV SCEV
              | SCEVAddRec SCEV SCEV Loop

Consult [the C++
source](https://github.com/llvm-mirror/llvm/blob/master/include/llvm/Analysis/ScalarEvolutionExpressions.h)
for more gory details.

Out of all of the above variants of the `SCEV` data type, `SCEVAddRec`
(an *add recurrence*) is the most important.  A `SCEVAddRec S X L`
object describes an expression defined in the loop `L` that is equal
to `S` on the zeroth iteration of the loop[^zeroidx] and is
incremented by `X` every time a backedge in `L` is taken.  `S` needs
to be invariant with respect to the loop `L` (by definition, it must
dominate the loop entry), but `X` need not be[^fullstory].  In
particular, `X` can itself be an add recurrence in the same loop.

[^zeroidx]: I will consistently use a zero indexed trip number.

[^fullstory]: Things are a little bit more complicated than that, and
    the ADT shown here does not tell the fully story; but as a first
    approximation this is fine.

An add recurrence is the only way ScalarEvolution can
meaningfully[^meaningfully] describe a value varying across the
iterations of a loop.  It can be seen as a precise (but fairly
general) definition of an "induction variable".

[^meaningfully]: ScalarEvolution can also describe a loop varying
    value by wrapping the corresponding `llvm::Value` in a
    `SCEVUnknown`, but at that point it is just treating as an opaque
    input that it does not "understand".

In this post we will solely focus on *affine add recurrences*, the
(sub)set of add recurrences `SCEVAddRec S X L` such that both `S` and
`X` are invariant with respect to `L`.  Affine add recurrences are
(unsurprisingly) the most common kind of add recurrences seen in real
programs (though I will admit this first part is somewhat anecdotal),
and also the subset of add recurrences that ScalarEvolution is best at
manipulating.

An affine add recurrence `SCEVAddRec S X L` is denoted as
`{S,+,X}<L>`.  This notation needs a small tweak to generalize to
non-affine add recurrences, but we won't talk about that in this post.
For the rest of this post, "add recurrence" really means "affine add
recurrence".

The value of `{S,+,X}<L>` in the `I`th iteration (with a zero indexed
`I`) is `S + RepAdd(I, X)`.  `RepAdd(I, V)` is a function from `(ℕ,
{0, 1}^k)` to `{0,1}^k` for some `k`, defined as:

    RepAdd(0, V) = 0
    RepAdd(I + 1, V) = V + RepAdd(I, V)

where `+` is the standard wrapping bitwise addition for a `k` bit
value.  It may seem odd to define `RepAdd` this way since given what
we've seen so far, defining it as integer multiplication should have
been fine.  However, this definition makes reasoning about integer
overflow more obvious in some cases e.g. when the bitwidth of the add
recurrence is less than the bitwidth required to hold the loop's trip
count.

One more notational thing before we dive in: by "trip count" I mean
"the number of times the body of the loop executes".  This is one more
than the number of times the backedge of the loop is taken.

# Integer overflow in add recurrences

## Definition

An add recurrence `{S,+,X}<L>` of bitwidth `N` is defined to be (with
`M` `=` `N + 1`):

 - `<nsw>` only if `sext({S,+,X}) to iM` evaluates to the same value
   as `{sext S to iM,+,sext X to iM}` for all iterations of the loop.
   This is equivalent to saying `sext(S + RepAdd(I, X)) to iM` `==`
   `(sext S to iM) + RepAdd(I, (sext X to iM))` for all `0` `<=` `I`
   `<` `TripCount`.

 - `<nuw>` only if `zext({S,+,X}) to iM` evaluates to the same value
   as `{zext S to iM,+,zext X to iM}` for all iterations of the loop.
   This is equivalent to saying `zext(S + RepAdd(I, X)) to iM` `==`
   `(zext S to iM) + RepAdd(I, (zext X to iM))` for all `0` `<=` `I`
   `<` `TripCount`.

This is (not coincidentally) similar to how we define integer overflow
for other operations like addition and subtraction.  Since the `<nsw>`
and the `<nuw>` clauses are symmetrical, the rest of the post will
only mention `<nsw>` under the assumption that the points being made
can be "easily extended" to the `<nuw>` case.

## Non-overflowing increment versus non-overflowing add recurrence

Now we come to the meat of this post, which is some discussion around
how the `<nsw>` ness of an add recurrence relates to the `<nsw>` ness
of the operation generating its backedge value.

Consider an add recurrence `{S,+,X}<L>`.  Concretely, it is equivalent
to the SSA value `%AddRec` in:

    L:
      %AddRec = phi i32 [ %S, %loop.entry ], [ %AddRec.Inc, %loop ]
      %AddRec.Inc = add i32 %AddRec, %X
      br i1 <condition>, label %loop, label %loopexit

Here “`{S,+,X}<L>` is `<nsw>`" implies that _if_ the backedge is
taken when `%AddRec` is `K` (say), _then_ adding `%X` to `K` does not
sign overflow.  This can be proved by induction on `P(I) = sext(S +
RepAdd(I, X)) == sext(S) + RepAdd(I, sext(X))`.  The full proof is
left as an exercise to the reader™.

The important thing to note is that the `<nsw>` ness of `{S,+,X}<L>`
does **not** imply that `add i32 %AddRec, %X` does not overflow for
all iterations of the loop -- in fact, given the IR above, an `<nsw>`
on `{S,+,X}` is consistent with `add i32 %AddRec, %X` sign-overflowing
on the last iteration of the loop.

[^analysis]: By "does not prevent" I mean "is congruent with".  SCEV
    is an analysis and as such does not "cause" things to be true or
    false in the IR.

It directly follows that all add recurrences in a loop with a trip
count of `1` are `<nsw>` and `<nuw>`.

## Overflow in post-increment add recurrences

Re-examining the IR we looked at earlier

    L:
      %AddRec = phi i32 [ %S, %loop.entry ], [ %AddRec.Inc, %loop ]
      %AddRec.Inc = add i32 %AddRec, %X
      br i1 <condition>, label %loop, label %loopexit

we need to note that the SCEV expression for `%AddRec.Inc` is also a
first class add recurrence in its own right: `{S+X,+,X}<L>`.  It has
its own behavior regarding `<nsw>` and `<nuw>` which follow from the
definitions stated earlier.  This behavior is related to but is in
general *different* from the `<nsw>` and `<nuw>` behavior of
`{S,+,X}<L>`.

For instance, in

    L:
      %AddRec = phi i32 [ INT_SMAX, %loop.entry ], [ %AddRec.Inc, %loop ]
      %loop.ctrl = phi i1 [ true, %loop.entry ], [ false, %L ]
      %AddRec.Inc = add i32 %AddRec, 1
      ;; Backedge is taken exactly once
      br i1 %loop.ctrl, label %loop, label %loopexit

going by the rules we've seen so far, the add recurrence corresponding
to `%AddRec`, `{INT_SMAX,+,1}<L>`, cannot be marked `<nsw>`, but the
one corresponding to `%AddRec.Inc`, `{INT_SMIN,+,1}<L>`, can be.  The
converse is true for

    L:
      %AddRec = phi i32 [ INT_SMAX - 1, %loop.entry ], [ %AddRec.Inc, %loop ]
      %loop.ctrl = phi i1 [ true, %loop.entry ], [ false, %L ]
      %AddRec.Inc = add i32 %AddRec, 1
      ;; Backedge is taken exactly once
      br i1 %loop.ctrl, label %loop, label %loopexit

where the the add recurrence corresponding to `%AddRec.Inc`,
`{INT_SMAX,+,1}<L>`, cannot be marked `<nsw>`, but the one
corresponding to `%AddRec`, `{INT_SMAX-1,+,1}<L>`, can be.
