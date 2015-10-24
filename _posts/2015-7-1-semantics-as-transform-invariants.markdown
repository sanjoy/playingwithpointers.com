---
layout: post
title:  "semantics as transform invariants"
permalink: semantics-as-transform-invariants.html
keywords: "semantics, program optimization, C, C++, undefined behavior"
---

Program optimization (via optimizing compilers) is usually framed as a
semantic preservation problem.  The programming environment assigns
some sort of meaning to the program being executed, and it is the job
of the optimizing compiler to preserve this meaning as it transforms
the program.  This is usually a chicken and egg problem -- the
semantics tend to depend on what you can implement efficiently -- and
many times the semantics of a construct is intentionally tuned *just
right* to allow certain kinds of transformations.  An example of this
sort of thing is the dreaded "undefined behavior" in C and C++[^hist].

[^hist]: The story goes that most of undefined behavior in C and C++
    was historically intended to keep the language specification
    independent of specific machine details.  But enabling compiler
    optimizations is currently a major use of undefined behavior.

# semantics and transforms

I propose another way to think about semantics in the presence of an
optimizer -- explicitly model a set of program transformations within
the programming language specification.  Have these transforms
axiomatically be semantics preserving, and have the semantics of a
program be a function of the semantics of the set of programs you get
by repeated application of these transforms[^self].

[^self]: This will have to be accompanied by some mechanism to avoid
    circular dependencies.

The memory models for Java and C++ are classic examples.  Currently
they're specified by a (somewhat complex) partial order that seemingly
*just so happens* to let the compiler do the transforms that it wants
to do.  If we're okay with making the optimizer a first class citizen
within language semantics, then we could instead state the "base"
semantics in terms of a sequentially consistent programming
environment (easy to specify) with a set of allowed re-orderings
(e.g. `r0 = *a; r1 = acquire-load b` $$\Rightarrow$$ `r1 =
acquire-load b ; r0 = *a`) that don't need further justification.
This is how most people reason about the memory model anyway.

A second example is [non-wrapping (`nuw` or `nsw`) arithmetic in
LLVM][arithmetic].  There have been many discussions on
[llvmdev][llvmdev] on what the *meaning* of a ["poison value"][poison]
should be, and as far as I can tell, there is currently no widely
accepted answer.  Here too we could choose to acknowledge the
optimizer in LLVM's semantics and state some transforms (like `(sext
(add nsw A B))` $$\Rightarrow$$ `(add (sext A) (sext B))`) as being
axiomatically meaning preserving.

A third example: a language specification could state that it is
always legal to move division operations from point $$A$$ to point
$$B$$ as long as $$B$$ is not reached if $$A$$ is not reached.
Division by zero can then be separately defined to trap
deterministically, and not have arbitrary undefined behavior.

[llvmdev]: http://lists.cs.uiuc.edu/pipermail/llvmdev/

What happens if your program changes behavior because of one of these
transforms?  I think we have some flexibility here.  We could
interpret behavior change due to axiomatically legal transforms as
"non determinism".  The implementation is allowed to have the program
evaluate to what any of the transformed programs would evaluate to,
and the program will have to deal with that somehow.  We could make a
more extreme assertion and interpret behavioral changes due to
axiomatically legal transforms as undefined behavior -- programs are
well defined only if they do not change observable behavior on the
application of an axiomatically legal transform.  There is a spectrum
of possibilities here.

# but ...

It may feel uncomfortable to tie the set of legal transforms this
directly to the language specification, and give off the impression
that getting a smarter compiler would require changing the language.
I don't think this is a big concern.  First of all, locking the
compiler out of optimizations is a possibility no matter how you
specify your semantics.  And by no means should the axiomatic
transforms be the *only* legal transforms -- they're just a way to
*specify* language semantics -- and they should be aggressively
exploited to derive other transforms.  For instance, using `(sext (add
nsw a b))` $$\Rightarrow$$ `(add nsw (sext a) (sext b))` we can prove
`(icmp slt a (add nsw a 1))` $$\Rightarrow$$ `true` since

<div>
\(\begin{aligned}
                    &amp; \; \texttt{(icmp slt a (add nsw a 1))} \texttt{} &amp; \text{} \\
\Longleftrightarrow &amp; \; \texttt{(icmp slt (sext a) (sext (add nsw a 1)))} \texttt{} &amp; \text{property of sext and slt} \\
\Rightarrow &amp; \; \texttt{(icmp slt (sext a) (add (sext a) (sext 1)))} \texttt{} &amp; \text{axiom} \\
\Longleftrightarrow &amp; \; \texttt{true} \texttt{} &amp; \text{true for all a} \\
\end{aligned}\)
</div>
<div>&nbsp;</div>

Slight digression: note that we cannot have `(sext (add nsw a b))`
$$\Longleftrightarrow$$ `(add nsw (sext a) (sext b))` as an axiom,
since if it were an axiom we could replace `true` with `(icmp slt a
(add nsw a 1))`, which would be weird.  And this transform does not
*have to happen*, and `(icmp slt a (add nsw a 1))` could also evaluate
to `false` if `a` was `INT_SMAX`.

# summary

Apart from proving the legality of transforms by showing that they
preserve semantics, I propose defining some bits of *semantics* as
what is preserved by axiomatically legal transforms.  I think this
approach has potential to simplify some corner cases in programming
language specification.

[poison]: http://llvm.org/docs/LangRef.html#poison-values
[arithmetic]: http://llvm.org/docs/LangRef.html#id51
