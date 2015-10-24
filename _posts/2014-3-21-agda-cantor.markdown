---
layout: post
title:  "cantor's diagonal argument in agda"
permalink: agda-cantor.html
keywords: "cantor, agda, math, proof, dependent types"
---

Cantor's diagonal argument, in principle, proves that there can be no
bijection between $$\mathbb{N}$$ and $$\{0, 1\}^\omega$$ ($$\omega$$
here is countable infinity, the cardinality of $$\mathbb{N}$$).
Depending on what logic you operate in (classical versus constructive)
this has implications on the relative cardinality of $$\mathbb{N}$$
and $$\mathbb{R}$$ ("is $$\mathbb{R}$$ bigger, in some sense of the
word, than $$\mathbb{N}$$?").  The proof itself is constructive, and
can be modeled within a theorem prover like Agda (or Coq) without
artificially introducing LEM.  This post is about modeling it in Agda.

First, some bookkeeping

{% highlight agda %}
module Cantor where

open import Data.Nat
open import Data.Product
open import Relation.Binary.PropositionalEquality
{% endhighlight %}

Then we define negation, as usual, using $$\bot$$,

{% highlight agda %}
data ⊥ : Set where

¬ : ∀ {ℓ} → Set ℓ → Set ℓ
¬ p = p → ⊥
{% endhighlight %}

and introduce a `Bit` type

{% highlight agda %}
data Bit : Set where
  Z : Bit -- "Zero"
  O : Bit -- "One'
{% endhighlight %}

and a simple utility function

{% highlight agda %}
flip : Bit → Bit
flip Z = O
flip O = Z
{% endhighlight %}

One way to model $$\{0, 1\}^\omega$$ (denoted here as $$\mathbb{R}$$
for fun, but we haven't proven any relation of that set with the set
of real numbers) is as a function from $$\mathbb{N}$$ to $$\{0, 1\}$$.

{% highlight agda %}
ℝ : Set
ℝ = ℕ → Bit
{% endhighlight %}

I was actually stuck for a while doing this proof because I tried
modeling $$\{0, 1\}^\omega$$ as a coinductive list of `Bit`s.  Turns
out working with function application is much easier.

Cantor's argument is proof by contradiction: it proceeds by showing
that given a mapping $$f : \mathbb{N} \mapsto \{0, 1\}^\omega$$ ,
there is an $$r \in \{0, 1\}^\omega$$ such that $$\forall n \cdot f(n)
\neq r$$.  This implies that $$f$$ cannot also be a surjective
function, and hence isn't a bijection.

In Agda, we model $$f$$ as a value of type $$\Omega$$,

{% highlight agda %}
Ω : Set
Ω = ℕ → ℝ
{% endhighlight %}

and inequality between $$a, b \in \{0, 1\}^\omega$$ as $$\exists n
\cdot a \downarrow n \neq b \downarrow n$$ where $$x \downarrow y$$
means "the $$y^{th}$$ digit of $$x$$".  In Agda, we create a data-type
`Different` such that `Different a b` is populated (i.e. there is a
value of that type) iff `a` and `b` are different by the above
criterion.

{% highlight agda %}
data Different (a b : ℝ) : Set where
  different : (n : ℕ) → ¬ (a n ≡ b n) → Different a b
{% endhighlight agda %}

We use `Different` to define `NonExistent`, such that for `o : Ω` and
`r : ℝ`, `NonExistent o r` is populated iff all values taken by `o` is
different from `r`, by the above definition of "different".  Note the
bracketing in `non-existent` (as opposed to `different`) -- it makes
all the difference in the world!

{% highlight agda %}
data NonExistent (order : Ω)  (r : ℝ) : Set where
  non-existent : ((n : ℕ) → Different (order n) r) →
                   NonExistent order r
{% endhighlight %}

Cantor's trick was, given a mapping $$f : \mathbb{N} \mapsto \{0,
1\}$$, to create a value $$v \in \{0, 1\}$$ such that it was different
from all values taken by $$f$$ at at least one "digit".  Specifically,
the $$n^{th}$$ digit of $$v$$ would be the inverse of the $$n^{th}$$
digit of $$n^{th}$$ value produced by $$f$$:

{% highlight agda %}
construct : Ω → ℝ
construct f = λ n → flip (f n n)
{% endhighlight %}

Once set up this way, the proof itself is surprisingly simple -- we
just need one additional simple lemma stating that `flip x` is never
equal to `x`:

{% highlight agda %}
flip-lemma : (x : Bit) → ¬ (x ≡ flip x)
flip-lemma Z ()
flip-lemma O ()
{% endhighlight %}

The proof asserts (using the dependent product type `Σ` defined in
`Data.Product` to model $$\exists$$) that given a mapping $$o :
\mathbb{N} \mapsto \{0, 1\}^\omega$$, we can find $$r$$ such that
everything $$o$$ produces is different from $$r$$.

{% highlight agda %}
cantor : (o : Ω) → Σ ℝ (λ r → NonExistent o r)
{% endhighlight %}


The $$r$$ we produce is given by `construct o`, and the proof by a
simple variation on `flip-lemma` that tells us that $$\forall n \cdot
o(n) \downarrow n \neq r \downarrow n$$.

{% highlight agda %}
cantor o = construct o , non-existent (
             λ n → different n (flip-lemma (o n n)))
{% endhighlight %}

$$\Box$$
