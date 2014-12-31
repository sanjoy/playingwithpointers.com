---
layout: post
title:  "solving linear range checks"
permalink: solving-linear-range-checks.html
---

# context

Some "managed" programming languages do automatic, compulsory range
checks on array accesses, and invoke some kind of error condition if
the array access is out of bounds.  This is in contrast to C'ish
languages where an out of bounds array access is undefined behavior
(even though any sane container will at least `assert` on bad
accesses).

Doing bounds checking on every array access can be expensive, however,
and optimizing away redundant array bounds checks is crucial to
achieving acceptable performance.  To this end, compilers will
sometimes split a loop's iteration space (the values assumed by its
induction variable) into sections where the range checks can be proved
away and sections where it cannot.  This can be a net win in cases
where the actual iteration space the loop runs in has a large
intersection with the section of the iteration space ranges checks
were proved away for.

As an example, consider:

    for (i = 0; i < n; i++)
	  array[i] = -1;

If we split the loop's iteration space this way:

	len = length(array)
    for (i = 0; i < min(n, len); i++)
	  array[i] = -1;
    
    for (i = min(n, len); i < n; i++)
	  array[i] = -1;

the first loop provably requires no range checks.  If `n` is always
`length(array)` or smaller, the second loop does not run at all, and
we've eliminated 100% of all range checks.

# the problem

To be able to split iteration spaces as shown above, we would like to
derive the set of values of `i` for which expressions like
`array[a + b * i]` provably pass the bounds check.  Normally this is
fairly simple arithmetic; but we'd like to consider programming
languages with well-defined wrapping overflow semantics
(i.e. `INT32_MAX + 1` is `INT32_MIN`).  Wrapping overflow semantics
makes things difficult because certain basic arithmetic properties we
all know and love do not apply -- `a < (b + 1)` does not imply `(a -
1) < b`, for example.  One way to deal with this complexity is to
consider the possibility for overflow at every step and either show
that it doesn't happen or that it doesn't matter.  The aim of this
post is to develop a different approach that I feel is more principled
to think in.

This post does not constitute a proof, but I think it can be extended
to be one with some effort.

## notation

We operate on $$N$$ bit machine integers, which really are elements of
the set $$\{0, 1\}^{N} = T$$. $$(k)^{N}$$ is an element of $$T$$ (and
hence an $$N$$-tuple) all of whose elements are $$k$$.

$$\Delta$$ is a mapping from $$T$$ to $$\mathbb{Z}$$.  $$\Delta(t)$$
is $$t$$ interpreted as an integer in base 2. $$\Delta$$ is injective,
but not surjective.  $$\Delta^{-1}$$ is defined on all integers less
than $$2^{N}$$ and greater than $$-1$$.

$$\Gamma$$ is a mapping from $$T$$ to $$\mathbb{Z}$$.  $$\Gamma(t)$$
is $$t$$ interpreted as an integer in 2's complement. $$\Gamma$$ is
injective, but not surjective.  $$\Gamma^{-1}$$ is defined on all
integers less than $$2^{N-1}$$ and greater than $$-1-2^{N-1}$$.

The following are relations between $$T$$ and $$T$$ (i.e. a subset of
$$T \times T$$)

 * $$\prec$$ is "signed less than": $$p \prec q \iff \Gamma(p) < \Gamma(q)$$
 * $$\preceq$$ is "$$\prec$$ or equal": $$p \preceq q \iff \Gamma(p)
   \leq \Gamma(q)$$
 * $$\sqsubset$$ is "unsigned less than": $$p \sqsubset q \iff
   \Delta(p) < \Delta(q)$$
 * $$\sqsubseteq$$ is "$$\sqsubset$$ or equal": $$p \sqsubseteq q \iff
   \Delta(p) \leq \Delta(q)$$

We will use $$\textrm{mod}$$ as the remainder function: $$a \mod b$$
is $$r \in \mathbb{Z}$$ such that $$0 \leq r < b$$ and $$a = k \times
b + r$$ for some $$k \in \mathbb{Z}$$.

The next two are functions from $$T \times T$$ to $$T$$

 * $$\oplus$$ is wrapping binary addition: $$a \oplus b =
   \Delta^{-1}((\Delta(a) + \Delta(b)) \mod 2^{N})$$

 * $$\otimes$$ is wrapping binary multiplication: $$a \otimes b =
   \Delta^{-1}((\Delta(a) \times \Delta(b)) \mod 2^{N})$$

$$\oplus$$ and $$\otimes$$ "just work" on integers represented as twos
complement which is *brilliant* but out of scope for this post.

## the problem

With the above notation, `array[a + b * i]` does not fail its bounds
check if

$$\begin{equation}
0 \preceq a \oplus (b \otimes i) \prec l \qquad ...\; (1)
\end{equation}$$

where $$l$$ is `length(array)` and $$l \succeq (0)^{n}$$.  The
alternative, $$l \prec (0)^{n}$$, is not interesting since in that
case there are no solutions (a negative "length" is also nonsensical
in the real world).

The solution set interpreted as integers represented in 2's complement
may not be a contiguous set -- e.g. if $$(N, a, b, l)$$ is $$(8, 0,
13, 10)$$, the solution set for $$i$$ is $$\{-118, -98, -59, -39, 0,
20, 40, 59, 79, 99\}$$

## solutions

Given that $$l \succeq (0)^{N} $$, we can write $$(1)$$ as

$$a \oplus (b \otimes i) \sqsubset l \qquad ...\; (2)$$

We let $$A = \Delta(a)$$, $$B = \Delta(b)$$ and $$L = \Delta(l)$$.
Then, by definition of $$\otimes$$ and $$\oplus$$, if $$i$$ is a
solution to $$(2)$$, then $$\Delta(i)$$ is a solution to $$(3)$$ and
if $$I$$ is a solution to $$(3)$$ and $$\Delta^{-1}$$ is defined on
$$I$$ then $$\Delta^{-1}(I)$$ is a solution to $$(2)$$.

[^proof]: frankly, I don't think this will be difficult to prove, as
    2's complement addition and multiplication is *defined* keeping
    the parallel with integer addition and multiplication in mind.
    But do think the proof will be tedious.

$$(A + ((B \times I) \mod 2^{N})) \mod 2^{N} < L \qquad ... \; (3)$$

We can "common out" the remainder operation:

$$(A + (B \times I)) \mod 2^{N} < L \qquad ... \; (4)$$

The interesting thing to note is that $$(4)$$ is really a *family* of
equations:

$$k \times 2^{N} \leq A + (B \times I) < k \times 2^{N} + L, \; k \in
\mathbb{Z} \qquad ... \; (5)$$

Since we are now in $$\mathbb{Z}$$land, we solve $$(5)$$ using
standard arithmetic:

If $$B > 0$$ then

$$\left\lceil\frac{k \times 2^{N} - A}{B}\right\rceil \leq I < \left\lceil \frac{k \times  2^{N} + L - A}{B} \right\rceil, \; k \in \mathbb{Z}$$

If $$B < 0$$ then

$$\left\lfloor \frac{k \times  2^{N} + L - A}{B} \right\rfloor < I \leq \left\lfloor\frac{k \times 2^{N} - A}{B}\right\rfloor, \; k \in \mathbb{Z}$$

In any case, for every $$k \in \mathbb{Z}$$ we have a range of values
for $$I$$ that satisfy $$(3)$$.  If we denote the solution set for a
given $$k$$ as a function $$f$$ of $$k$$, then $$f$$ is periodic with
an interval of $$B$$. Thus we can compute the full solution set for
$$I$$ as $$\bigcup_{k = 0}^{k = B - 1} f(k)$$.

Given a set of solutions for $$I$$, $$S$$, we map them to solutions
for $$(2)$$ and hence $$(1)$$ as follows:

 * if $$t \in S$$ and $$0 \leq t < 2^{N}$$ then $$\Delta^{-1}(t)$$ is
   a solution for $$(2)$$

 * if $$t \in S$$ and $$t < 0$$ or $$t \geq 2^{N}$$ then write $$t$$
   as $$q \times 2^{N} + r$$ where $$0 \leq r < 2^{N}$$.  Note that if
   $$t$$ is a solution to $$(3)$$ then so is $$r$$.  Since
   $$\Delta^{-1}(r)$$ is defined, it is a solution to $$(2)$$.

## ranges

So far we've solved $$(2)$$ in terms of individual values.  In some
cases this set of values can be "easily" split into a union of ranges.

For example say for a given $$k$$ we have $$m \leq I < n$$ as a
solution to $$(5)$$.  If $$\exists \, r_0, r_1, k \in \mathbb{Z}$$
such that $$0 \leq r_0 < r_1 < 2^{N}$$ and $$m = k \times 2^{N} +
r_0$$ and $$n = k \times 2^{N} + r_1$$ then every $$s \in T$$ such
that $$\Delta^{-1}(r_0) \sqsubseteq s \sqsubset \Delta^{-1}(r_1)$$ is
a solution to $$(2)$$.  If $$\exists \, r_0, r_1, k \in \mathbb{Z}$$
such that $$0 \leq r_0 , r_1 < 2^{N}$$ and $$m = k \times 2^{N} +
r_0$$ and $$n = (k + 1) \times 2^{N} + r_1$$ then every $$s \in T$$
such that $$\Delta^{-1}(r_0) \sqsubseteq s$$ is a solution to $$(2)$$.
More such cases can easily be derived.

Being able to split the solution set into ranges is important because
that is what allows us to break up a loop's iteration space cheaply
(i.e. with almost zero additional overhead).

# conclusion

I will end with some random notes:

 * it is probably possible to extend this approach to work with
   non-linear functions like `array[a + b * i + c * i * i]`.  But I
   doubt that's anything more than solely interesting on a theoretical
   level.

 * it will be nice to try to formalize some of this in Coq or Agda.  I
   don't think I currently have the chops to do that, though.

 * I have not really come across or tried to derive an algebra of
   comparison operators in a world with wrapping arithmetic.  Perhaps
   there is a simpler approach on those lines I'm missing?
