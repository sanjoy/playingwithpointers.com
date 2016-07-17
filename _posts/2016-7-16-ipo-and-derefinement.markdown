---
layout: post
title:  "Inter-Procedural Optimization and Derefinement"
permalink: ipo-and-derefinement.html
keywords: "compilers, LLVM, IPO, COMDAT, vague linkage"
---

*This is a summary of an issue that was semi-recently fixed in
[LLVM](http://llvm.org/PR26774) and
[GCC](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=70018).  It merits
a blog post because the issue is somewhat subtle, and a central place
to refer to can be helpful.*

# Setting the Stage

In this post we will focus on C++ `inline` functions.  The problem
described here may apply to other cases as well, but we won't focus on
those.

C++ `inline` functions are usually defined in header files that are
included in multiple translation units.  The *intent* is to inline
them at all call sites, but some call-sites may not actually inline
these functions (to cap code size, for instance) in which case an
out-of-line copy of the definition is required.  In order to have an
out-of-line definition when needed, compilers typically emit a copy of
the function body in each translation unit that includes the header
(the header defining the `inline` function, that is), and at link time
the linker chooses one of the (potentially multiple) bodies it has
access to as the definitive copy of the function and links all
un-inlined call sites to call into that.  There is some more detail
about the process at <http://www.airs.com/blog/archives/52>.

Since the compiler can see the definition of C++ `inline` functions
when optimizing its callers, it is tempting to do some
inter-procedural optimization (IPO) even if we don't inline the
function bodies.  For instance, if we know the call target does not
read or write memory, we can do dead store elimination across the
call-site.

This post will show that IPO like the above is generally not sound for
C++ `inline` functions.

# Claims

 1. Given two differently (but correctly!) optimized versions of the
    same source level function, we may be able to prove things about
    one of the copies that are not valid for the other.

 2. From (1) it follows that inter-procedural optimizations are
    generally not valid if the call site can ultimately link to a
    differently optimized version of the same source level function.
    This means IPO across call-sites calling C++ `inline` functions is
    unsound if we link two differently optimized object files together
    (i.e. `clang -O1` vs. `clang -O3`).

 3. "Differently optimized" does not necessarily mean "different
    optimization pipeline".  It is possible for the same function to
    be differently optimized just by virtue of being in a different
    context.  Therefore IPO across C++ `inline` functions call
    boundaries is incorrect even if every object file being linked
    together is optimized identically (i.e. `clang -O3` vs. `clang
    -O3`).


# As-if Execution and Refinement

Many optimizations involve the compiler "choosing" one valid execution
from many possible valid executions.

For instance, consider this snippet:

{% highlight C++ %}
bool f(std::atomic_int& ptr) {
  int val_a = ptr.load(std::memory_order_relaxed);
  int val_b = ptr.load(std::memory_order_relaxed);
  return val_a == val_b;
}
{% endhighlight %}

As written, `f` can either return `true` or `false`: there could be a
concurrent thread writing different values to `ptr` while `f`
executes, and the two loads from `ptr` may or may not observe
different values.  However, a compiler is allowed to (expected, even)
to first optimize the above to

{% highlight C++ %}
bool f_opt(std::atomic_int& ptr) {
  int val = ptr.load(std::memory_order_relaxed);
  return val == val;
}
{% endhighlight %}

and then to

{% highlight C++ %}
bool f_opt(std::atomic_int& ptr) {
  return true;
}
{% endhighlight %}

This is legal since even though `f` is _allowed to_ return `false`, it
does not _have to_ return `false` even in the face of racing writes.
That is it does not _have to_ see different values from the two reads
from `ptr` -- we can always optimize it *as if* both the reads from
`ptr` saw the same value.

The key observation here is that `f` and `f_opt` are **not**
equivalent -- it is legal to replace `f` with `f_opt` (that is,
`f_opt` is a valid implementation of `f`), but not the other way
around.  Henceforth, let's call going from `f` to `f_opt` (and similar
cases) *refinement* and going the other way from `f_opt` to `f` (and
similar cases) *derefinement*.  As stated, *derefinement* is not a
valid optimization in the traditional sense.

Refinement is not specific to atomic operations and multi-threaded
programs.  Given

{% highlight C++ %}
bool g(bool b) {
  if (b)
    return true;
  int unused = 1 / 0;
  return false;
}
{% endhighlight %}

we can produce

{% highlight C++ %}
bool g_opt(bool b) {
  return true;
}
{% endhighlight %}

by refining away undefined behavior.

Clang will also do as-if optimizations on `malloc` (though I
personally find this specific transform somewhat questionable):

{% highlight C++ %}
bool h() {
  int* ptr = (int *)malloc(sizeof(int));
  bool result = ptr != nullptr;
  free(ptr);
  return result;
}
{% endhighlight %}

to

{% highlight C++ %}
bool h_opt() {
  return true;
}
{% endhighlight %}

Talking about LLVM IR directly, many basic arithmetic optimizations
are refinement operations since the IR specifies an `undef` value.
For instance, replacing `x - x` with `0` refines the expression from
computing "`undef` if `x` is `undef`, `0` if `x` isn't
`undef`"[^undefbits] to "`0` for all values of `x`".

[^undefbits]: Strictly speaking, this is not complete since LLVM
    allows individual bits to be `undef`, but hopefully it gets the
    gist across.

## Derefinement breaks static analysis

Given the optimization transforming

{% highlight c++ %}
bool f(std::atomic_int& ptr) {
  int val_a = ptr.load(std::memory_order_relaxed);
  int val_b = ptr.load(std::memory_order_relaxed);
  if (val_a != val_b)
    write_to_memory();
}
{% endhighlight %}

to

{% highlight c++ %}
bool f_opt(std::atomic_int& ptr) { }
{% endhighlight %}

static analysis on `f_opt` is not necessarily valid on `f`.  For
instance, `f_opt` does not read or write memory while `f` does, and if
we optimize the caller of `f_opt` based on the assumption that it does
not read or write memory then changing the call site to call `f`
instead of `f_opt` will retroactively invalidate the optimization.

This demonstrates claim (1): *given two differently optimized versions
of the same source level function, we may be able to prove things
about one of the copies that are not valid for the other.* Note that
`f` is a trivially "optimized" version of itself.

# "Differently optimized" does not mean "different optimization pipeline"

To see why claim (3) is true, consider something like:

{% highlight c++ %}
// x.hpp
class F {
  void f(std::atomic_int& ptr) {
    if (g(ptr) != g(ptr))
      read_and_write_memory();
  }
  int g(std::atomic_int& ptr);
};
{% endhighlight %}


{% highlight c++ %}
// x.cpp
#include "x.hpp"

int F::g(std::atomic_int& ptr) {
  return ptr.load(std::memory_order_relaxed);
}

void external_caller_0(F &f, int* value, std::atomic_int& v) {
  *value = 10;
  f.f(v);
  *value = 20;
}
{% endhighlight %}

{% highlight c++ %}
// y.cpp
#include "x.hpp"

void external_caller_1(F &f, std::atomic_int& v) {
  f.f(v);
}
{% endhighlight %}

When optimizing `X.cpp` it is possible for `F::g` to get inlined into
`F::f` and then for `F::f` to ultimately be optimized to an empty
function.  This could then justify an inter-procedural optimization to
optimize away the store of `10` to `value` in `external_caller_0`,
which would be bad if the call site ultimately called the copy of
`F::f` present in the `Y.cpp` translation unit.  The copy of `F::f`
present in the `Y.cpp` translation unit will not have inlined `F::g`
(since it can't even see it) and thus will contain a viable call to
`read_and_write_memory` (which presumably reads and writes memory).
Therefore the store elimination we did in `external_caller_0` will be
rendered invalid retroactively if we replace the call site in
`external_caller_0` to call `F::f` from the `Y.cpp` translation unit.

You can find an "exploit" based on this concept at
<https://github.com/sanjoy/comdat-ipo>, but note that this bug is now
fixed in both clang and GCC.

# Solutions

Firstly, I'll note that this problem disappears in "whole program
optimization" like situations where the optimizer runs after the
definitive copy of each C++ `inline` functions has been selected.

Here are some ways to solve this in a traditional, "optimize and
codegen to `.o` files, and then link" setting:

 - Link a call site calling a C++ `inline` function only to the exact
   definition that the compiler saw when optimizing the caller.  This
   will require some smartness in the linker to avoid excessive code
   bloat, but it allows unrestricted IPO across C++ `inline` call
   sites.

 - Don't do IPO over call sites that call C++ `inline` functions.
   This is the fix implemented in clang today.  I don't know what fix
   was implemented in GCC for this.

 - Do IPO across C++ `inline` call boundaries, but only before the
   inline candidates have had any refinement.

I want to expand on the third option a little, since it begs the
interesting question: what optimizations don't involve refinement?
Here are some examples of non-refining optimizations:

Since racing on non-atomic reads and writes is undefined behavior,
optimizing:

{% highlight c++ %}
int f(int *ptr) {
  *ptr = 20;
  return *ptr;
}
{% endhighlight %}

to

{% highlight c++ %}
int f(int *ptr) {
  *ptr = 20;
  return 20;
}
{% endhighlight %}

is not refinement.  Optimizing

{% highlight c++ %}
int f() {
  if (false)
    foo();
  bar();
}
{% endhighlight %}

to

{% highlight c++ %}
int f() {
  bar();
}
{% endhighlight %}

isn't refinement either -- both the original and transformed programs
have the exact same set of behaviors -- "call `bar`".

Informally, to decide whether a transform involves refinement or not
we can ask the following question: is the inverse of the said
transform a correct optimization?  Since refinement transforms remove
behaviors, their inverses _add_ behaviors, something a correct
optimization typically[^examples] cannot do.  Therefore optimizations
whose inverses are correct optimizations cannot be refining
optimizations.

[^examples]: Please let me know if there are counterexamples to this.
