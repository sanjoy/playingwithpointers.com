---
layout: post
title:  "Seemingly Impossible Turing Machines"
keywords: "cantor, agda, math, proof, dependent types"
date: 2019-6-29
needsMathJAX: True
---

In this post I'll explore a concept I discovered in a [very interesting writeup](http://math.andrej.com/2007/09/28/seemingly-impossible-functional-programs/) by Martin Escardo on Andrej Bauer's blog.  The title of this post is an homage to the title used by Martin Escardo: "Seemingly impossible functional programs".

I have made the following changes from the original post:

 - I don't use point-set topology.  Instead I provide a more direct proof for the existence of modulus of uniform continuity.
 - The accompanying implementation is in a non-lazy programming language (C++) which, I believe, makes the algorithms easier to understand.

# The Setup and the Punchline

In this post we consider Turing Machines that takes an infinite bit sequence as input and produce one bit as output[^multibits].  Henceforth in this post "Turing Machine" will be abbreviated as "TM" and the set of all infinite bit sequences will be denoted by $$\mathbb{B}$$.

[^multibits]: All of this easily generalizes to Turing Machines that produce some constant number of bits as output.

An infinite bit sequence, $$b \in \mathbb{B}$$, is an oracle that takes as input an index $$i \in \mathbb{N}$$, and returns the bit in the bit sequence at index $$i$$.  Not all infinite bit sequences are computable so not all $$b \in \mathbb{B}$$ can be implemented by a TM[^halting].

[^halting]:  E.g. consider the bit sequence where bit i is 1 iff the i'th TM halts.

Furthermore, we only consider TMs that halt for all input bit sequences. That is, we only consider TMs that compute total functions of type $$\mathbb{B} \to \{0, 1\}$$.  We'll call the set of these TMs $$\mathbb{T}$$.

Let $$\textrm{Indices}(M, b) \subseteq \mathbb{N}$$ be the set of indices $$M$$ queries $$b$$ during execution.  It is fairly obvious that $$\forall b$$, $$\textrm{Max}(\textrm{Indices}(M, b))$$ is finite:  since $$M(b)$$ terminates, $$\lvert \textrm{Indices}(M, b)\rvert$$ is finite, and therefore $$\textrm{Max}(\textrm{Indices}(M, b))$$ is a finite natural number.

However, a less obvious fact is that for any $$M \in \mathbb{T}$$ there is an *input independent upper bound* on the indices it will probe its input at!  That is, $$\forall M \in \mathbb{T}$$ we can compute an $$n \in \mathbb{N}$$ such that $$\forall b \in \mathbb{B}$$, $$\textrm{Max}(\textrm{Indices}(M,b)) \lt n$$.

For the rest of the post, the assertion made above will be referred to as **the theorem**.

# The Proof

## Some Examples and Intuition

It may be helpful to first try to "break" the theorem for intuition.

Consider an $$M \in \mathbb{T}$$ that reads an integer $$n < 256$$ from the first 8 bits of the bit sequence and uses that to compute an index, $$f(n)$$ into the bit sequence.  In this case the constant upper bound on $$\textrm{Indices}(M,b)$$ is $$Max_{0 \le n \lt 256}(f(n))$$.

We could try to use some variable length encoding for the index that does not "bake in" a bitwidth by e.g. interpreting $$111...<\textrm{n times}>0$$ as the integer $$n$$.  In this case you can also construct a bit sequence that repeats $$1$$ infinitely, for which the TM does not halt.  This violates our precondition that the TM must halt for all input bit sequences.

Informally, an $$M \in \mathbb{T}$$ needs to "decide" whether to ask for bit $$I+1$$ based on the first $$I$$ bits only.  If $$M$$ does not have an input independent upper bound on the maximum index it inspects, it must read bit $$I+1$$ (or greater) for *some* input bit sequence and so $$M$$ must ask for bit $$(I+1)^{th}$$ for _some_ value of the first $$I$$ bits. A malicious input oracle should be able to pick this value for the first $$I$$ bits and *force* $$M$$ to ask for bit $$I+1$$.  Furthermore the malicious oracle should be able to do this for all $$I$$, causing $$M$$ to never halt.  The proof is just a more rigorous version of this argument.

## Proof by Contradiction

The proof will proceed by showing that **if** an $$M \in \mathbb{T}$$ does not have an input independent upper bound on the indices it accesses **then** there is an input $$b \in \mathbb{B}$$ for which $$M$$ does not halt.  This gives us a proof by contradiction because all $$M \in \mathbb{T}$$ are supposed to be halting, by assumption.

For $$b \in \{0, 1\}^n$$ let $$S(b)$$ be the set of infinite bit sequences that have $$b$$ as a prefix.  Let $$MI(M, b)$$ be $$\textrm{Max}(\textrm{Indices}(M, b))$$, with $$M \in \mathbb{T}$$ and $$b \in \mathbb{B}$$.

Formally, "$$M$$ does not have an input independent upper bound on the indices it accesses" can be stated as $$\forall n \in \mathbb{N}, \exists b \in \mathbb{B}$$, $$\textrm{MaxIndex(M, b)} \gt n$$.

Given an $$M \in \mathbb{T}$$, we construct a infinite bit sequence, $$NH \in \mathbb{B}$$ ($$NH$$ for "Not Halting"), that "computes" (read on for why I have scare quotes here) the bit at index $$I$$ as follows:

 1. It keeps some state that persists across executions -- an $$s \in \mathbb{N}$$ (initial value: $$0$$) and a $$bs \in \{0, 1\}^s$$ (initial value: the empty bitvector).  $$bs$$ is a finite prefix of the infinite bit sequence $$NH$$ represents, and is the portion of the infinite bit sequence that it has already "committed to".
 2. If $$I \lt s$$ then it returns $$bs[I]$$ (i.e. it returns the answer that it has already committed to).
 3. Otherwise it finds a bit vector $$b \in \{0, 1\}^{I+1}$$ that is an extension of $$bs$$[^extension] (there are $$2^{I+1-s}$$ such $$b$$ s), such that $$\{MI(M, B) \textrm{ for } B \in S(b)\} \subseteq \mathbb{N}$$ has no upper bound.  That is, $$\forall n \in \mathbb{N}$$, $$\exists B \in S(b)$$, $$MI(M, B) \gt n$$.  This predicate will later be referred to as $$\textrm{Unbounded}(b)$$.
 4. It sets $$bs$$ to $$b$$ and $$s$$ to $$I+1$$.
 5. It returns $$b[I]$$.

[^extension]: I.e. $$bs$$ is a prefix of $$b$$.
 
Firstly, note that step (3) is not an algorithm, i.e. it is not obvious that it can be computed by a TM.  There may be some clever way around this (or a proof showing that there isn't), but so far I haven't found one.  So this proof only shows the existence of a bit sequence in $$\mathbb{B}$$, but does not prove that it is computable.

Secondly, (3) implies that $$M(NH)$$ will not halt.  This is because if $$M$$ halts after when evaluating $$NH(I_H)$$, in step (3) we will have $$\forall B \in S(b)$$, $$MI(M, B)$$ $$=$$ $$I_H$$, which contradicts the condition in (3).

Finally we need to prove that (3) always succeeds.  We can prove this via induction.

Let $$P(i)$$ be the assertion that "step (3) succeeds when the oracle is called for the $$i^{th}$$ time".  Without loss of generality we assume the oracle is called with increasing indices.

**Base case.**

In the very first call $$bs$$ is the empty string and $$S(\textrm{empty string})$$ is $$\mathbb{B}$$.  Thus $$\forall n \in \mathbb{N}$$, $$\exists B \in S(b)$$, $$MI(M, B) \gt n$$ is just our "$$M$$ does not have an input independent upper bound on the indices it accesses" precondition and is true by assumption.

**$$\textbf{P(i)}$$ assuming $$\textbf{P(i - 1)}$$.**

Let $$\textrm{Bounded}(x)$$ $$\equiv$$ $$\exists c \in \mathbb{N}$$, $$\forall B \in S(x)$$, $$MI(M, B)$$ $$\lt$$ $$c$$.  Let $$A+X$$ mean "the concatenation of the two bitvectors $$A$$ and $$X$$".

We will be using the notation from the definition of $$NH$$ above -- $$bs$$ is the cached prefix from the previous call, $$I$$ is the index of the bit this $$i^{th}$$ call has to produce etc.  Let $$I+1-s$$ be $$L$$.  This is the length by which we will have to extend $$bs$$ to get $$b$$.

The proof is by contradiction.  Let's assume we are unable to find an $$I+1$$ sized extension of $$bs$$ in the $$i^{th}$$ invocation of the oracle.

Not being able to find a extension of $$bs$$ means that $$\neg$$ $$(\exists x \in \{0,1\}^{L}$$, $$\textrm{Unbounded}(b' + x))$$ $$\equiv$$ $$\forall x \in \{0,1\}^{L}, \textrm{Bounded}(b' + x)$$.  In other words, $$P(i)$$ fails when there is no way to extend $$bs$$ (of length $$s$$) by $$x$$ (of length $$L$$) such that $$\textrm{Unbounded}(bs + x)$$.

Expanding Bounded, we get $$\forall x \in \{0,1\}^{L}$$, $$\exists c \in \mathbb{N}$$, $$\forall B \in S(b' + x)$$, $$MI(M, B)$$ $$\lt$$ $$c$$.  Setting $$C$$ to be the maximum of all the $$2^{L}$$ $$c$$s, we get $$\exists C \in \mathbb{N}$$, $$\forall x \in \{0,1\}^{L}$$, $$\forall B \in S(b' + x)$$, $$MI(M, B)$$ $$\lt$$ $$C$$.  This further simplifies to $$\exists C \in \mathbb{N}$$, $$\forall B \in \cup_{x \in \{0,1\}^{L}} S(b' + x)$$, $$MI(M, B)$$ $$\lt$$ $$C$$.  But $$\cup_{x \in \{0,1\}^{L}} S(b' + x)$$ is just $$S(b')$$, so the we really have $$\exists C \in \mathbb{N}$$, $$\forall B \in S(b')$$, $$MI(M, B)$$ $$\lt$$ $$C$$.

But this contradicts $$P(i-1)$$, so we must be able to find an $$I$$ sized extension of $$bs$$!

# Making it Real

Given the theorem, we can write an algorithm that computes what is called the "modulus of uniform continuity" in the [original post](http://math.andrej.com/2007/09/28/seemingly-impossible-functional-programs/) by Martin Escardo.  The modulus of uniform continuity is the smallest $$n \in \mathbb{N}$$ such that $$\forall a, b \in \mathbb{B}$$, $$a =_{n} b$$ $$\implies$$ $$M(a) = M(b)$$ where $$M \in \mathbb{T}$$, and $$p =_{n} q$$ means the first $$n$$ bits of $$p$$ and $$q$$ are identical.  This modulus is really just the $$\textrm{Max}_{b \in \mathbb{B}}$$, $$MI(M, b)$$ we saw earlier.  Since $$M$$ only looks at the first $$n$$ bits in its input (at most), it can't distinguish between two inputs that differ at indices greater than the modulus.

To compute the modulus of uniform continuity, we first define a way to construct a special oracle, $$\mathbb{O}(bv)$$, from a finite bitvector prefix $$bv \in \{0, 1\}^n$$.

 - For indices $$i \lt n$$, $$\mathbb{O}(bv)$$ returns $$bv[i]$$.
 - For indices $$i \ge n$$, $$\mathbb{O}(bv)$$ returns a sentinel value.
 - We modify $$M$$ so that the sentinel value causes $$M$$ to return early with a sentinel value as well.  This modification can be done mechanically e.g. by a compiler.
 - $$\mathbb{O}(bv)$$ keeps track of the indices for which it returned the sentinel value, for later examination.
 
Using $$\mathbb{O}$$ we can compute the modulus of uniform continuity for an $$M \in \mathbb{T}$$ as follows:

 1. Set $$U$$ to $$0$$.
 2. For $$bv$$ in $$\{0, 1\}^{U}$$:
    1. Let $$O = \mathbb{O}(bv)$$.
    2. Execute $$M(O)$$.
    3. If $$\textrm{Max}(O.\textrm{indices_queried}) \ge U$$:
       1. Set $$U$$ to $$\textrm{Max}(O.\textrm{indices_queried})$$ and goto 2.
 3. Return $$U$$.

This always terminates -- iff $$U$$ is the modulus of uniform continuity $$M(O)$$ will not query any higher indices for any $$bv$$ and the algorithm will not increment $$U$$ any further.

With this algorithm we can implement a variety of things that seem impossible at first glance:

 - Given an $$M \in \mathbb{T}$$ we can either produce a $$b \in \mathbb{B}$$ such that $$M(b)$$ is $$0$$ or definitely say that there is no such $$b \in \mathbb{B}$$.

 - We can check if two $$M_0 \in \mathbb{T}$$ and $$M_1 \in \mathbb{T}$$ compute identical functions.  We can do this by checking if the TM $$M(b) \equiv M_0(b) = M_1(b)$$ returns false for any $$b \in \mathbb{B}$$.

# A C++ Implementation

I have implemented the ideas in this blog post [in C++](https://github.com/sanjoy/impossible-programs/blob/master/main.cc).  Here is a quick overview in case you want to take a look:

 - The `BitSequence` class models an oracle that can be queried.  However it is not really an oracle since it only represents computable bit sequences.

 - `BitSequence::Get` returns an `std::optional` as the sentinel value.  For convenience we have an `ASSIGN_OR_RETURN` macro (as a poor man's `Maybe` monad) to reduce boilerplate.

 - The fundamental primitive is `ForSome` which decides whether a function of type $$\mathbb{B} \to \{0, 1\}$$ returns true for any input.  This can, in turn, be used to implement the predicate `ForEvery`(M) = $$\forall a$$, $$M(a)$$, which lets us compute the modulus of uniform continuity as the smallest $$n$$ such that $$\forall a, b \in \mathbb{B}$$, $$a =_{n} b$$ $$\implies$$ $$M(a) = M(b)$$.

 - Finally, the C++ implementation has an optimization in `ForSome` that makes it search exponentially only across the bits requested by the TM, not across all bits with indices less than the currently largest requested index.

I'd encourage implementing this in favorite programming language, it is a fun exercise!

# What I Would Like to Understand Better

I'd like to understand the role of computability here.  To prove the theorem we exploited the fact that the input bit sequence does not need to be computable.  Can the proof be strengthened?  Or is the prof "tight" and there exist TMs with an unbounded modulus of continuity if we restrict its inputs to computable bit sequences?
