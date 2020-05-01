---
layout: post
title:  "Understanding Ladner's Theorem"
needsMathJAX: True
date: 2020-5-7
---

As you probably know, whether $$P = NP$$ is a [major unsolved problem](https://en.wikipedia.org/wiki/P_versus_NP_problem) in computer science.

Even if you believe $$P \ne NP$$, it is tempting to think that _NP_ $$=$$ _P_ $$\cup$$ _NP_-complete -- that every problem in _NP_ can either be solved in polynomial time or is expressive enough to encode _SAT_.

Ladner's theorem states that this intuition isn't true by showing the existence of [_NP_-intermediate](https://en.wikipedia.org/wiki/NP-intermediate) problems: problems that are in _NP_ but are neither in _P_ nor _NP_-complete (assuming $$P \ne NP$$).  The proof in [the Arora/Barak book](http://theory.cs.princeton.edu/complexity/) is quite interesting, and this is a short writeup on how I understood it intuitively.  I have sacrificed rigor for intuition; the full proof can be found in the book and various other places.

The proof describes a language that is _NP_-intermediate by construction.  The construction almost feels like cheating as you'll see.  But the proof is technically correct, which is the [best kind of correct](https://www.youtube.com/watch?v=hou0lU8WMgo).

## Influencing Complexity by Padding

The proof utilizes a trick of padding problem instances to enable "faster" algorithms.

Consider a problem, _POLYSAT_, with instances of the form $$\{S + “1” * 2^{\lvert S\rvert}, S \in SAT\}$$, where
 - _SAT_ is the set of all SAT instances
 - $$S + “1” * k$$ means $$S$$ followed by $$k$$ $$“1”$$s
 - $$\lvert S \rvert$$ is the length of $$S$$

Given a string $$S_P$$, the goal is to return $$1$$ if $$S_P$$ is of the form $$S + “1” * 2^{\lvert S\rvert}$$ and $$S$$ is satisfiable, and $$0$$ otherwise.

_POLYSAT_ can be solved in "polynomial time": we can naively check all  $$2^{\lvert S \rvert}$$ possibilities in polynomial time because the size of the input is $$2^{\lvert S \rvert}+\lvert S \rvert$$.

For contrast, we wouldn't have gotten this exponential speedup had the instances been of the form $$\{S + “1” * \lvert S\rvert^c, S \in SAT\}$$ where $$c$$ is some constant -- the extra padding of size $$\lvert S \rvert ^c$$ lets us "hide" only a polynomial number of steps, and so this variation is not in $$P$$ unless $$P=NP$$.

## Choosing the Correct Amount of Padding

The[^oneproof] proof of Ladner's theorem constructs a problem (henceforth referred to as $$\mathbb{L}$$) by padding _SAT_ by just the right amount: not enough to put the language in _P_ (so less than $$2^{\lvert S \rvert}$$), but enough that it isn't _NP_-complete (so more than $$\lvert S \rvert ^ c$$).  And it uses a clever self-referential trick to accomplish this.

[^oneproof]: There are at least two proofs of Ladner's theorem.  In this blog post I'm only discussing the proof in the Arora/Barak book.

Instances of $$\mathbb{L}$$ are of the form $$\{S + “1” * \lvert S\rvert^{H(\lvert S\rvert)} \textrm{ for } S \in SAT\}$$ and (like _POLYSAT_) the goal is to decide whether the embedded _SAT_ expression is satisfiable.  In other words, given a string $$S_L$$ the algorithm has to return $$1$$ if:
 - $$S_L$$ is of the form $$S + “1” * \lvert S\rvert^{H(\lvert S\rvert)}$$
 - $$S$$ is a valid _SAT_ problem
 - $$S$$ is satisfiable

Otherwise the algorithm has to return $$0$$.

$$H(x)$$ is defined so that iff the $$i^{th}$$ Turing Machine solves $$\mathbb{L}$$ in polynomial time then $$H(x) = i$$ for sufficiently large $$x$$, otherwise $$H(x)$$ is an monotonically increasing non-constant function.  The exact definition is listed later.

We will show that both "$$\mathbb{L}$$ is in _P_" and "$$\mathbb{L}$$ is _NP_-complete" imply $$P = NP$$.  This means $$\mathbb{L}$$ must be _NP_-intermediate if $$P \ne NP$$.

**(1) $$\mathbb{L}$$ is not in _P_**

If $$\mathbb{L}$$ is in _P_ then $$H(\lvert S \rvert)$$ is $$O(1)$$, since for large enough $$\lvert S \rvert$$ it computes the fixed index of the Turing Machine that solves $$\mathbb{L}$$ in polynomial time.  But then $$\mathbb{L}$$ is just _SAT_ with a polynomial amount of padding so if $$\mathbb{L}$$ is in _P_ so is _SAT_.  This leads to $$P = NP$$.

**(2) $$\mathbb{L}$$ is not _NP_-complete**

If $$\mathbb{L}$$ is $$NP$$ complete then there is (by definition) a polynomial reduction, $$\mathbb{G}$$, from _SAT_ instances to instances of $$\mathbb{L}$$.  Let's say $$\mathbb{G}$$ runs in $$o(n^c)$$ steps where $$n$$ is the size of the _SAT_ instance being reduced.  And $$\mathbb{G}$$ maps a _SAT_ instance, $$T$$, to the string $$S + “1” * \lvert S \rvert^{H(\lvert S\rvert)}$$ where $$S$$ is also a _SAT_ instance.  We will show that there is a constant $$t_{max}$$ such that if $$\lvert T \rvert \ge t_{max}$$ then $$\lvert S \rvert \lt \lvert T \rvert$$.  This means we could build a polynomial time SAT solver that repeatedly applies $$\mathbb{G}$$ to reduce a SAT instance until it is of size $$\le t_{max}$$, after which the problem can be brute forced in constant time.  This again leads to $$P = NP$$.

$$\lvert T \rvert \ge t_{max}$$ $$\Rightarrow$$ $$\lvert S \rvert \lt \lvert T \rvert$$ can be shown as follows:

$$\mathbb{G}$$ runs in $$O(\lvert T \rvert^c)$$ so $$\exists$$ $$t_0$$ such that $$\lvert T \rvert \ge t_0$$ $$\Rightarrow$$ the reduction algorithm runs in at most $$k * \lvert T \rvert^c$$ steps where $$k$$ and $$c$$ are both constants.  $$\mathbb{G}$$ can write at most one character in each step of execution so the length of the "reduced" instance of $$\mathbb{L}$$ can at most be $$k * \lvert T \rvert^c$$ characters longer than $$\lvert T \rvert$$.  I.e. $$\lvert T \rvert \ge t_0$$ $$\Rightarrow$$ $$\lvert S\rvert + \lvert S \rvert^{H(\lvert S\rvert)} \le \lvert T \rvert + k * \lvert T \rvert^c$$.

We can manipulate the above to get $$\lvert S \rvert^{H(\lvert S\rvert)}$$ $$\lt$$ $$\lvert S\rvert + \lvert S \rvert^{H(\lvert S\rvert)}$$ $$\le$$ $$\lvert T \rvert + k * \lvert T \rvert^c$$ $$\le$$ $$(k + 1) * \lvert T \rvert^c$$ $$\Rightarrow$$ $$\lvert S \rvert^{H(\lvert S\rvert)}$$ $$\le$$ $$(k + 1) * \lvert T \rvert^c$$.

$$H$$ is not $$o(1)$$ (as shown in the "$$\mathbb{L}$$ is not in _P_" section) so $$\exists t_1$$ such that $$\lvert T \rvert \ge t_1$$ $$\Rightarrow$$ $$H(\lvert T \rvert) \gt (c + 1)$$.  Let $$t_2 = max(t_1, k + 1)$$.  Then $$\lvert T \rvert \ge t_2$$ $$\Rightarrow$$ $$(k + 1) * \lvert T \rvert^c \le \lvert T \rvert ^ {c+1} \lt \lvert T \rvert^{H(\lvert T\rvert)}$$.  This implies $$\lvert S \rvert \lt \lvert T \rvert$$ by contradiction: $$\lvert T \rvert \le \lvert S \rvert$$ and $$(k + 1) * \lvert T \rvert^c \lt \lvert T \rvert^{H(\lvert T\rvert)}$$ implies $$(k + 1) * \lvert T \rvert^c \lt \lvert S \rvert^{H(\lvert S\rvert)}$$ but we also have $$\lvert S \rvert^{H(\lvert S\rvert)} \le (k + 1) * \lvert T \rvert^c$$.

Finally, we set $$t_{max}$$ to $$max(t_0, t_2)$$ to get the result we set out to prove.
  
### Defining H

$$H(x)$$ was defined as "iff the $$i^{th}$$ Turing Machine solves $$\mathbb{L}$$ in polynomial time then $$H(x) = i$$ for sufficiently large $$x$$, otherwise $$H(x)$$ is an monotonically increasing non-constant function of $$x$$".  As written, this does not work: $$\mathbb{L}$$ needs to be in _NP_ but this definition of $$H$$ does not even look decidable!

To get around this, we _approximate_ the above definition so that it is computable.  Specifically, $$H(x)$$ finds the Turing Machine with index $$\lt x$$ that computes $$\mathbb{L}$$ correctly in $$\lvert s \rvert ^ {log_2(log_2(x))}$$ steps for all $$s \in \{0, 1\}^*$$ with $$\lvert s \rvert \le log_2(x)$$.  If there is no such Turing Machine then $$H(x)$$ is $$x$$.

Concretely, $$H(x)$$ (of type $$\mathbb{N} \to \mathbb{N}$$) is computed as follows:

1. For $$i \in [0, x)$$:
2. &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;For $$s \in \{0, 1\}^*$$ and $$\lvert s \rvert \le log_2(x)$$:
3. &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Run $$M_i$$[^mi] for $$\lvert s \rvert ^{log_2(log_2(x))}$$ steps with input $$s$$
4. &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;If $$M_i$$ halts and its result matches $$\mathbb{L}(s)$$[^Ls_notation]
5. &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Return $$i$$
6. Return $$x$$

This algorithm takes a polynomial in $$x$$ number of steps: step 3 is run $$x^2$$ times and each execution takes a polynomial function[^sim] of $$log_2(x)^{log_2(log_2(x))}$$ steps.  Furthermore, $$log_2(x)^{log_2(log_2(x))}$$ is $$o(x)$$ since for $$x \ge 70000$$ $$log_2(x)^{log_2(log_2(x))} \lt x$$.

To prove $$x \ge 70000$$ $$\Rightarrow$$ $$log_2(x)^{log_2(log_2(x))} \lt x$$, first apply $$log_2$$ twice on both expressions to get $$F(x)$$ as $$2 * log_2(log_2(log_2(x)))$$ and $$G(x)$$ as $$log_2(log_2(x))$$.  $$F(70000) \lt 4.007 \lt 4.008 \lt G(70000)$$ and $$\frac{d}{dx} F(x) - G(x)$$ is $$\frac{- ln(ln(x)) + 2 + ln(ln(2))}{x ln(2) ln(x) ln(log_2(x))}$$ which is $$\lt 0$$ for $$x \gt e^{e^{2 + ln(ln(2))}}$$ and $$e^{e^{2 + ln(ln(2))}} = 167.6.. \lt 70000$$.

Since $$H(x)$$ is polynomial in $$x$$, $$\mathbb{L}$$ is in _NP_: given a string of length $$l$$ a non-deterministic Turing Machine will "guess" $$0 \le k \le n$$ and:
 - Check if the first $$k$$ elements of the string form a satisfiable _SAT_ expression
 - Check that the last $$n - k$$ elements of the string are $$“1”$$ repeated
 - $$n - k = H(k)$$ where $$H(k)$$ can be computed in $$P$$

[^sim]: This polynomial depends on how "efficiently" $$M_i$$ can be simulated.
[^mi]: $$M_i$$ is the $$i^{th}$$ Turing Machine.
[^Ls_notation]: $$\mathbb{L}(s)$$ is $$1$$ if $$s$$ is satisfiable, and $$0$$ if not.
