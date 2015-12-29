---
layout: post
title:  "a problem with LLVM's undef"
permalink: problem-with-undef.html
keywords: "LLVM, compilers, semantics"
---

LLVM has a special value in its SSA value hierarchy called `undef`
that is used to model (amongst other things) reads from uninitialized
memory.  Semantically, an `undef` value has a potentially new bit
pattern of the compiler's choosing at each *use site*, meaning that
values like `xor i32 %a, %a` need not always evaluate to `0` when
`%a` is `undef` (even though they're allowed to).  This lack of
consistency lets LLVM get away without allocating registers to
remember a specific "version" of `undef`.

Another way to look at this is that `undef` isn't a really SSA
*value*, and uses of an `undef` value are also its "defs".  This leads
to some interesting restrictions on data flow analysis via control
flow.

For instance, consider this:

    declare i1 @predicate()
    declare void @use(i32)
    
    define void @f(i32 %d) {
     entry:
      %division_unsafe = icmp eq i32 %d, 0
      br i1 %division_unsafe, label %leave, label %loop.ph
    
     loop.ph:
      br label %loop
    
     loop:
      %iv = phi i32 [ 0 , %loop.ph ], [ %iv.inc, %be ]
      %iv.inc = add i32 %iv, 1
      %p = call i1 @predicate()
      br i1 %p, label %divide, label %be
    
     divide:
      %q = udiv i32 1, %d
      call void @use(i32 %q)
      br label %be
    
     be:
      %be.cond = icmp ult i32 %iv, %d
      br i1 %be.cond, label %loop, label %leave
    
     leave:
      ret void
    }

Is it legal to hoist the division `%q` in `divide` to the loop
preheader?  At first, it does look like it is legal, since the loop
preheader is guarded on the `%d` not being `0`.  However, in the
transformed program

    declare i1 @predicate()
    declare void @use(i32)
    
    define void @f(i32 %d) {
     entry:
      %division_unsafe = icmp eq i32 %d, 0
      br i1 %division_unsafe, label %leave, label %loop.ph
    
     loop.ph:
      %q = udiv i32 1, %d
      br label %loop
    
     loop:
      %iv = phi i32 [ 0 , %loop.ph ], [ %iv.inc, %be ]
      %iv.inc = add i32 %iv, 1
      %p = call i1 @predicate()
      br i1 %p, label %divide, label %be
    
     divide:
      call void @use(i32 %q)
      br label %be
    
     be:
      %be.cond = icmp ult i32 %iv, %d
      br i1 %be.cond, label %loop, label %leave
    
     leave:
      ret void
    }

we have a problem.  If `%d` is `undef`, then `%division_unsafe = icmp
eq i32 undef, 0` is allowed to be `false` while `%q = udiv i32 1,
undef` is allowed to have undefined behavior (by choosing `0` for
`undef`).  If `@predicate` always returns `false` then the original
program is perfectly well defined for `%d` = `undef` while the
transformed program isn't, after doing a very reasonable transform.

Generally, with `undef` in the play, control dependence in the control
flow graph cannot be used to derive facts about SSA values.  If the
value we're interested in happens to be `undef`, then it can "pretend"
to satisfy the predicate the control dependence is on while
"pretending" to *not* satisfy the predicate on later control dependent
uses of the same value.

This problem isn't unique to branches -- many kinds of correlated
value or predicate analysis are problematic.  Consider `%expr =
smax(%a+1, %a)-smin(%a+1, %a)`, with `smax` implemented using `select`
and `icmp`.  Is `%expr` always non-zero?  In the absence of `undef`,
`%expr` is either `-1` or `1`.  But if `%a` is `undef`, then `%expr`
is `undef` as well (and thus can be `0`).  The key problem here is
that `a >s b ? a : b` does not actually compute `smax(a,b)` in the
presence of `undef` (in that, it doesn't always result in a value that
is `>= a`).
