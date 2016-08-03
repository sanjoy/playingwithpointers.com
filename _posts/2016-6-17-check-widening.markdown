---
layout: post
title:  "Check Widening in LLVM"
permalink: check-widening-in-llvm.html
keywords: "exceptions, java, llvm"
---

*This post describes infrastructure that has gone in to LLVM piecemeal
over the last couple of months.  All of the information in this post
is scattered throughout in commit messages on
[llvm-commits](http://lists.llvm.org/pipermail/llvm-commits/) and
email threads on
[llvm-dev](http://lists.llvm.org/pipermail/llvm-dev/).  This post is
intended to present a coherent story for people not actively involved
in the original discussions and without the spare time to stitch
together the big picture from individual commits and emails.*


# Motivation: Checks in Managed Languages

In "safe" languages like Java, it is the virtual machine's job to
ensure that illegal operations (like dereferencing bad memory or
unsound type coercions) does not lead to the program into arbitrarily
bad states.  This is typically enforced by adding runtime checks to
certain operations to check for violations.  Field accesses elicit a
null check, array loads and stores have a range check (and in some
cases a type check), type casts check the cast is well-formed etc.
For this post we'll focus on range checks only, but the general idea
is applicable to any kind of runtime check.

Let's start with a simple example:

{% highlight java %}
void foo(int[] arr) {
  arr[0] = 0;
  arr[1] = 1;
  arr[2] = 0;
  arr[3] = 1;
}
{% endhighlight %}

Pretending there are no null checks (for brevity, this also applies to
the rest of the post), the code above will be lowered into:

{% highlight java %}
void _foo(int[] arr) {
  if (!(0 u< arr.length)) throw OutOfBounds;
  arr[0] = 0;
  if (!(1 u< arr.length)) throw OutOfBounds;
  arr[1] = 1;
  if (!(2 u< arr.length)) throw OutOfBounds;
  arr[2] = 0;
  if (!(3 u< arr.length)) throw OutOfBounds;
  arr[3] = 1;
}
{% endhighlight %}

*Notationally, I'll use `_<function>` to denote a "lowered" version of
`<function>` that has some checks made explicit. `u<` denotes the
"unsigned less than" comparison.  `lhs u< rhs` is equal to (but
cheaper than) `0 s<= lhs && lhs s< rhs` given `rhs` is positive,
where`s<` denotes the "two's complement signed less than" operation.*

The codegen above is pretty bad.  Predictable branches are cheap, but
not free, and we'd like to do better than emit four compare-branches
for something as simple as `foo`.

For a moment if we focus *solely* on guaranteeing safety, we notice
some redundancy; we could optimize the above to:

{% highlight java %}
void _foo(int[] arr) { /// version_a
  if (!(3 u< arr.length)) throw OutOfBounds;
  arr[0] = 0;
  arr[1] = 1;
  arr[2] = 0;
  arr[3] = 1;
}
{% endhighlight %}

and be "just as safe".  No array store will actually store to invalid
memory, and if we do end up throwing an `OutOfBounds` exception (
`ArrayIndexOutOfBoundsException` really, but I don't like typing) then
we know that at least one following array accesses would have been
illegal.

However, in Java, exceptions like `ArrayIndexOutOfBounds` are
recoverable.  Someone could have called `foo` as

{% highlight java %}
void caller() {
  int[] arr = new arr[3];
  try {
    foo(arr);
  } catch (Exception e) {
    assert(arr[1] == 1);
  }
}
{% endhighlight %}

[^clrrelaxed]: For instance, see "VI.Annex F Imprecise faults" in "Standard ECMA-335 Common Language Infrastructure (CLI)"

and `version_a` would be observably different for such a caller (some
languages explicitly allow this difference, though[^clrrelaxed]) -- it
would throw an exception without writing anything to `a[0]`, `a[1]` or
`a[2]`, when the original program would have written to `a[0]`, `a[1]`
and `a[2]`, and *then* thrown an exception.

Does this mean we're forever stuck generating code like `version_a`
above?[^betteridge] An important observation is that an actual out of
bounds array access is rare.  Despite out-of-bounds exceptions being
recoverable, in 99.99% (anecdotal ratio :) ) of the cases an out of
bounds exception is a *bug* in the application (and gets fixed), so it
is okay if we're slow (but correct!) in cases like `caller` above.

[^betteridge]: According to [Betteridge's law of headlines](https://en.wikipedia.org/wiki/Betteridge%27s_law_of_headlines) the answer is obviously no. :)

Let's make a change in how we represent range checks.  Instead of
throwing, we "deoptimize":

{% highlight java %}
void _foo(int[] arr) {
  // loc_0:
  if (!(0 u< arr.length)) deoptimize() [ "deopt"(<values_0>) ];
  arr[0] = 0;
  // loc_1:
  if (!(1 u< arr.length)) deoptimize() [ "deopt"(<values_1>) ];
  arr[1] = 1;
  // loc_2:
  if (!(2 u< arr.length)) deoptimize() [ "deopt"(<values_2>) ];
  arr[2] = 0;
  // loc_3:
  if (!(3 u< arr.length)) deoptimize() [ "deopt"(<values_3>) ];
  arr[3] = 1;
}
{% endhighlight %}

Deoptimization[^urs] discards the current runtime frame, and resumes
execution in the interpreter from a "safe" state.  In the lowering
shown above, if `arr.length` is `2` then we won't actually throw an
exception from compiled code, but will re-start execution in the
interpreter from `loc_2`, which will then immediately throw an
exception.  `<values_2>`, attached to the call instruction as an
["operand bundle"](http://llvm.org/docs/LangRef.html#operand-bundles)
contains all of the information required to construct the interpreter
frame(s) to restart execution from `loc_2`, as a sequence of SSA
values.

[^urs]: Hölzle, Urs, Craig Chambers, and David Ungar. “Debugging optimized code with dynamic deoptimization.” ACM Sigplan Notices. Vol. 27. No. 7. ACM, 1992.

The "failure paths" are now not explicit exception throws, but bails
to the interpreter; and we *can* optimize the above code to:

{% highlight java %}
void _foo(int[] arr) {
  if (!(3 u< arr.length)) deoptimize() [ "deopt"(<values_0>) ];
  arr[0] = 0;
  arr[1] = 1;
  arr[2] = 0;
  arr[3] = 1;
}
{% endhighlight %}

because if we do have a caller like

{% highlight java %}
void caller() {
  int[] arr = new arr[3];
  try {
    foo(arr);
  } catch (Exception e) {
    assert(arr[1] == 1);
  }
}
{% endhighlight %}

then `_foo` will jump back to the interpreter, and *the interpreter*
will execute the stores to `arr[0]`, `arr[1]` and `arr[2]` and then
throw an exception. As far as the caller is concerned, nothing
observably changed, but `_foo` will be faster in the very likely case
that there aren't any range check violations.  In the very unlikely
case that we do have a range check violation, `_foo` will have to pay
the penalty of deoptimization followed by the penalty of staying in
the interpreter till the end of the method[^healing].

[^healing]: Typically a JVM will have ways to heal such widened range
    checks back into normal range checks if the assumption of out of
    bounds access being "very unlikely" no longer holds for a
    particular check.

This technique can be applied to range checks without non-constant
indices too.  If we have

{% highlight java %}
void bar(int[] arr, int i) {
  arr[i]     = 10;
  arr[i + 1] = 20;
  arr[i + 2] = 30;
  arr[i + 3] = 40;
}
{% endhighlight %}

and the [math works
out](https://github.com/llvm-mirror/llvm/blob/master/lib/Transforms/Scalar/GuardWidening.cpp#L612),
then we can lower and optimize this to:

{% highlight java %}
void _bar(int[] arr, int i) {
  if (!(i       u< arr.length) ||
      !((i + 3) u< arr.length))
    deoptimize();
  
  // No more range checks.
  arr[i]     = 10;
  arr[i + 1] = 20;
  arr[i + 2] = 30;
  arr[i + 3] = 40;
}
{% endhighlight %}

The term "widening" here denotes that we're widening the previous
check to "fail more often", on a "broader" range of values.

# Why Guards?

## The Problem with Control Flow

There is a problem with the above approach.  Consider a case like this:

{% highlight java %}
void _foo(int[] arr) {
  bool condition = 0 u< arr.length;
  // loc_0:
  if (!(0 u< arr.length)) deoptimize() [ "deopt"(condition, ...) ];
  arr[0] = 0;
  // loc_1:
  if (!(1 u< arr.length)) deoptimize() [ "deopt"(<values_1>) ];
  arr[1] = 1;
}
{% endhighlight %}

Above, `condition` feeds into the interpreter state.  LLVM is allowed
(expected, even) to optimize this to:

{% highlight java %}
void _foo(int[] arr) {
  bool condition = 0 u< arr.length;
  // loc_0:
  if (!(0 u< arr.length)) deoptimize() [ "deopt"(false, ...) ];
  arr[0] = 0;
  // loc_1:
  if (!(1 u< arr.length)) deoptimize() [ "deopt"(<values_1>) ];
  arr[1] = 1;
}
{% endhighlight %}

but that is a problem if we widen the transformed program:

{% highlight java %}
void _foo(int[] arr) {
  bool condition = 0 u< arr.length;
  // loc_0:
  if (!(1 u< arr.length)) deoptimize() [ "deopt"(false, ...) ];
  arr[0] = 0;
  arr[1] = 1;
}
{% endhighlight %}

Now if `arr.length` is `1` then we'll deoptimize to the interpreter
with `false` as the value of `0 u< arr.length`!  This can be
arbitrarily bad.  E.g. say instead of `foo` we were optimizing:

{% highlight java %}
void strangeLove(int[] arr) {
  bool condition = 0 u< arr.length;
  arr[0] = 0;
  if (!condition) {
    /* FIXME: TODO: remove dead code. */
    launch_nukes();
  }
  arr[1] = 1;
}
{% endhighlight %}

As written above, `strangeLove` will never call `launch_nukes`, since
if `condition` is `false` (and we would have called `launch_nukes`),
we are guaranteed to throw an exception when accessing `arr[0]`.  But
if we optimize `strangeLove` to something like `_foo` above, then when
passed in an array of length `1`, we are going to enter the
interpreter with `condition` set to `false`, but will not fail the
range check on `arr[0]`.  This will spuriously call `launch_nukes`,
which is probably not a good thing.

## Enter Guards

What bit us above is that when we let the optimizer loose on `_foo`
for the first time, we told it that the deoptimizing path for the
first range check is executed if and only if `!(0 u< arr.length)`.
However, only half of that is true!  If we allow range check widening,
the deoptimizing path is executed if but **not** *only if* `!(0 u<
arr.length)`.  To be correct, we'll have to write our code in a way
that the correctly expresses the "if but not only if" sentiment.

The most obvious approach is to express the not-only-if'ness of the
condition directly in the expression feeding into the branch:

{% highlight java %}
void _foo(int[] arr) {
  bool condition = 0 u< arr.length;
  bool unknown_0 = create_unknown();
  // loc_0:
  if (!(0 u< arr.length) || unknown_0)
    deoptimize() [ "deopt"(condition, ...) ];
  arr[0] = 0;
  // loc_1:
  bool unknown_1 = create_unknown();
  if (!(1 u< arr.length) || unknown_1)
    deoptimize() [ "deopt"(<values_1>) ];
  arr[1] = 1;
}
{% endhighlight %}

Given the control flow above, the use of `condition` in the first
`deoptimize` call cannot be optimized to `false`: we know that if the
branch to `deoptimize` was not taken then `0 u< arr.length` is
definitely `true` (so we know the load from `arr[0]` is safe), but we
can't assume that if `deoptimize` was called, `0 u< arr.length` was
`false`.  Widening the first range check to include the second can
then be semantically seen as choosing a suitable value for
`unknown_0`.

However, this extra `create_unknown` call can get messy quickly by
creating incidental complexity. For instance, we'll have to state its
memory effects.  If it is `readnone` or `readonly` then what happens
when some of them get CSE'ed? If it is `readwrite` then does it
inhibit too much optimization?  To avoid all of that, and to have a
generally cleaner representation, we introduced [guard
intrinsics](http://llvm.org/docs/LangRef.html#llvm-experimental-guard-intrinsic)
to LLVM IR.  A `guard` intrinsic takes an `i1` as a parameter, and
expresses the following semantics internally:

{% highlight llvm %}
define void @guard(i1 %pred) {
  %realPred = and i1 %pred, undef
  br i1 %realPred, label %continue, label %leave

leave:
  call void @deoptimize() [ "deopt"(...) ]
  ret void

continue:
  ret void
}
{% endhighlight %}

A call to `@guard(i1 %condition)` guarantees that `%condition` is
`true` if it returns (if `%condition` is `false`, we'll break out of
the compiled code into the interpreter), but there is no guarantee
that if a guard deoptimizes then `%condition` was `false` -- a guard
can deoptimize "spuriously" by choosing `false` for the value of
`undef`.  Normally this kind of bitwise operation (`and i1 %pred,
undef`) will immediately be folded to `false`[^correctfolding], but
the "implementation" of `@guard` shown above is really only the
specification; we don't actually provide a body for the intrinsic, but
lower it directly to a call to `@deoptimize` guarded by an explicit
conditional branch.

[^correctfolding]: This fold will be a performance issue, since we'll
    branch to the interpreter unnecessarily, but it would be correct.
    Deoptimizing with the right interpreter state is always correct.

Using guards also benefits us indirectly by not having too many
unnecessary basic blocks that don't express user-level logic.  A
simpler control flow graph is better for compile time and memory
usage.

All in all, this is how the widening optimization can be expressed
using guards.  First

{% highlight java %}
void foo(int[] arr) {
  arr[0] = 1;
  arr[1] = 0;
  arr[2] = 1;
  arr[3] = 0;
}
{% endhighlight %}

gets lowered to:

{% highlight java %}
void _foo(int[] arr) {
  guard(0 u< arr.length);
  arr[0] = 1;
  guard(1 u< arr.length);
  arr[1] = 0;
  guard(2 u< arr.length);
  arr[2] = 1;
  guard(3 u< arr.length);
  arr[3] = 0;
}
{% endhighlight %}

*Note: we don't negate the condition, since `guard` deoptimizes if the
 condition passed to it is `false`.*

and then optimized and widened to:

{% highlight java %}
void _foo(int[] arr) {
  guard(3 u< arr.length);
  arr[0] = 1;
  arr[1] = 0;
  arr[2] = 1;
  arr[3] = 0;
}
{% endhighlight %}

and finally lowered to:

<a name="final-example"></a>
{% highlight java %}
void foo(int[] arr) {
  if (!(3 u< arr.length)) deoptimize();
  arr[0] = 1;
  arr[1] = 0;
  arr[2] = 1;
  arr[3] = 0;
}
{% endhighlight %}


# Putting it all Together

If you want to use check widening in LLVM for your compiler, you have
to

 - Implement some form of deoptimization (this is a fundamental change
   to your runtime), and use that to implement exception throws.

 - Represent checks that you want to widen as predicates passed to
   `guard` intrinsics.

 - Schedule your pass pipeline to run the
   [GuardWidening](https://github.com/llvm-mirror/llvm/blob/master/lib/Transforms/Scalar/GuardWidening.cpp)
   pass, and at some later point run the
   [LowerGuardIntrinsic](https://github.com/llvm-mirror/llvm/blob/master/lib/Transforms/Scalar/LowerGuardIntrinsic.cpp)
   pass (these are still experimental passes, so use at your own risk,
   don't use in production, no backward compatibility guarantees
   etc.).

 - Yell at me when things fall over. :)

{% hnlink https://news.ycombinator.com/item?id=12108674 %}
