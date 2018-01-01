---
layout: post
title:  "Certified Compilation in Agda"
redirect_from:
 - /agda-verified-compilation.html
keywords: "verified programming, agda, verified compilation, proof, dependent types"
date: 2013-4-29
---

Using dependent types, it is possible to specify contracts for Agda
programs at a very fundamental level. Today we'll see how to transform
an extremely simple tree-based calculator language to a stack-based
one; and use Agda to assert the correctness of our transformation. The
complete source code for this post is at [^1].

The tree-based language is defined by the following data-type, with
the obvious semantics:

{% highlight agda %}
data Exp : Set → Set₁ where
  ↑_ : {A : Set} → A → Exp A
  _plus_ : Exp ℕ → Exp ℕ → Exp ℕ
  _minus_ : Exp ℕ → Exp ℕ → Exp ℕ
  _eq_ : Exp ℕ → Exp ℕ → Exp Bool
  _lt_ : Exp ℕ → Exp ℕ → Exp Bool
  cond_then_else_ : {A : Set} → Exp Bool → Exp A → Exp A → Exp A
{% endhighlight %}

Note how dependent types are helpful already -- without them we would
not be able to elegantly assert [^2], for instance, that `lt` takes
two `Exp ℕ`s and maps them to an `Exp Bool`. The semantics are defined
by a function with the stereotypical name `eval` of type `Exp A → A`.

{% highlight agda %}
eval : {A : Set} → Exp A → A
eval (↑ value) = value
eval (a plus b) = eval a + eval b
eval (a minus b) = eval a ∸ eval b
eval (a eq b) with Data.Nat._≟_ (eval a) (eval b)
... | yes _ = true
... | no _ = false
eval (a lt b) with Data.Nat._≤?_ (eval a) (eval b)
... | yes _ = true
... | no _ = false
eval (cond c then t else f) = if eval c then eval t else eval f
{% endhighlight %}

Nothing unusual here, expect perhaps the implementation of `eval (a eq
b)` and `eval (a lt b)`. Boolean values aren't especially useful in
dependently-typed programming languages since they don't carry a proof
of why a proposition is true. Operations like `≟` and `≤` therefore
evaluate to a `Decidable` instance; which, apart from the result of the
comparision (the `yes` and `no` we're pattern matching on here), also
contain a proof term of why the proposition is true or false. Since we
don't need the proofs for this rather simple use-case, we merrily
ignore the same by underscores.

The stack-machine we'll compile to is a bit more interesting -- here
too we use dependent types to guarantee consistency as much as
possible. First of all, we use a stack that tracks the types of all
its elements separately:

{% highlight agda %}
data TypedStack : List Set → Set₁ where
  nil : TypedStack []
  push : {A : Set} {S : List Set} → A → TypedStack S → TypedStack (A ∷ S)
{% endhighlight %}

This signature ensures that, for instance, the first three elements of
a stack of type `TypedStack (ℕ ∷ ℕ ∷Bool ∷ S)` (for some `S`) will
have types `ℕ`, `ℕ` and `Bool`.

The stack machine has six bytecodes, `bcAdd`, `bcSub`, `bcEq`, `bcLt`,
`bcCond` and `push` (one of the constructors for `TypedStack`).

{% highlight agda %}
bcAdd : {S : List Set} → TypedStack (ℕ ∷ ℕ ∷ S) → TypedStack (ℕ ∷ S)
bcAdd (push a (push b rest)) = push (a + b) rest

bcEq : {S : List Set} → TypedStack (ℕ ∷ ℕ ∷ S) → TypedStack (Bool ∷ S)
bcEq (push a (push b rest)) with Data.Nat._≟_ a b
... | yes _ = push true rest
... | no _ = push false rest

bcCond : {S : List Set} {A : Set} → TypedStack (Bool ∷ A ∷ A ∷ S) →
         TypedStack (A ∷ S)
bcCond (push c (push x (push y rest))) = push (if c then x else y) rest
{% endhighlight %}

The bytecode types specify how the bytecodes will transform the
stack. A program in this context is essentially a composition of some
of the above bytecodes

{% highlight agda %}
StackProgram : Set → Set₁
StackProgram a = {S : List Set} → TypedStack S → TypedStack (a ∷ S)
{% endhighlight %}

and a term of type `StackProgram X` is a program that leaves behind a
value of type `X` when it's done executing. So, for instance

{% highlight agda %}
leaveBehindEleven : StackProgram ℕ
leaveBehindEleven = bcAdd ∘ push 5 ∘ push 6
{% endhighlight %}

is well typed but

{% highlight agda %}
popsEmptyStack : StackProgram ℕ
popsEmptyStack = bcAdd ∘ push 5
{% endhighlight %}

isn't.

Now we come to the compiler that transforms programs in the tree form
to equivalent programs in the stack-machine form. The compiler itself
is simple (some cases have been left out):

{% highlight agda %}
compile : {A : Set} → Exp A → StackProgram A
compile (↑ y) = push y
compile (a plus b) = bcAdd ∘ compile a ∘ compile b
compile (a eq b) = bcEq ∘ compile a ∘ compile b
compile (cond c then x else y) = bcCond ∘ compile c ∘ compile x ∘ compile y
-- ...
{% endhighlight %}

As a proof that the compiler actually preserves program semantics, we
look for a term, `verifyCompiler` of the type `{A : Set} → (exp : Exp
A) → IsCorrectFor exp` where `IsCorrectFor exp = (S : List Set) →
(compile exp {S} ≡ push{_}{S} (eval exp))`. In plain English, an
expression exp is correctly compiled, denoted as `IsCorrectFor exp`,
only if compiling and executing the stack-machine version is the same
as evaluating the tree version and pushing the evaluated value onto
the stack. The compiler is correct only if it correctly compiles all
expressions. If you've been following along, give writing
verifyCompiler yourself a shot!

Agda finds the simplest case for verifyCompiler obvious

{% highlight agda %}
verifyCompiler (↑ y) S = refl
{% endhighlight %}

To prove that we correctly compile `a minus b`, we need to show that
`compile (a minus b)` is the same function (`compile` returns a stack
program, which is essentially a function from `TypedStack` to
`TypedStack`) as `push (eval (a minus b))`. To do this, we first show
that since `compile b` is the same as `push (eval b)`, `compile (a
minus b)` is `bcSub ∘ compile a ∘ compile b` is `bcSub ∘ compile a ∘
(push (eval b))`. This is shown in `sub-prf₀`. Similarly, in
`sub-prf₁` we show that since `compile a` is the same as `push (eval
a)`, `bcSub ∘ compile a ∘ (push (eval b))` is the same as `bcSub ∘
(push (eval a)) ∘ (push (eval b))`. These two combined, by
transitivity, gives us our proof -- Agda is clever enough to see that
`bcSub ∘ (push (eval a)) ∘ (push (eval b))` reduces to `push ((eval a)
∸ (eval b))`.

{% highlight agda %}
verifyCompiler (a minus b) S =
  let inductionA = verifyCompiler a
      inductionB = verifyCompiler b
      sub-prf₀ = subst (λ term → compile (a minus b)
                       ≡ bcSub ∘ compile a ∘ term)
                 (inductionB S) refl
      sub-prf₁ = subst (λ term → bcSub ∘ compile a ∘ (push (eval b))
                        ≡ bcSub ∘ term ∘ (push (eval b)))
                 (inductionA (ℕ ∷ S)) refl
  in trans sub-prf₀ sub-prf₁
{% endhighlight %}

We slightly deviate from this approach when proving correctness when
compiling for `a lt b` and `a eq b` -- I had to case on the two
possibilities when comparing `a` and `b`.

Certified compilation is a rather [^3] interesting [^4] topic --
something I'd like to explore further. A compiler for something a
little more substantial than basic arithmetic should be a nice sequel.

[^1]: <https://github.com/sanjoy/Snippets/blob/master/ArithVerified/>
[^2]: also see <http://www.haskell.org/haskellwiki/GADT>
[^3]: <http://compcert.inria.fr/>
[^4]: <http://adam.chlipala.net/papers/CtpcPLDI07/CtpcPLDI07.pdf>
