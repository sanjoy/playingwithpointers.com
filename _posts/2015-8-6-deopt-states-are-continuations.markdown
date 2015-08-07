---
layout: post
title:  "deoptimization states are continuations"
permalink: deopt-states-are-continuations.html
---

For basic vocabulary related to deoptimization, I'll use terms as
defined by this post[^philip] by Philip.  Please take a look if you're
not conceptually familiar with deoptimization.

In a discussion with a few folks from the LLVM community, a question
came up about the nature of the "abstract VM state" a deoptimization
point deoptimizes to.  For instance if two readonly calls see the same
state of the heap, but have different deopt states, can they be
CSE'ed?  What happens if you inline a LLVM function compiled from java
into an llvm function compiled from C#?  What is the framework in
which we reason about these questions?

I think the right formalization of a call with a vm state (that may
deoptimize) is that, apart from the "regular" continuation being
passed in (ret addr + stack frame), a second continuation is passed in
the form of a VM state.  Since we have an interpreter, the vm state is
the data representation of the continuatino.  More specifically, the
"normal return continuation" is guarded with some specific constraints
being valid, and the caller will return to it if valid, else return to
this VMstate continuation.

This view lets us cleanly answer the most basic question about VM
states -- what happens when you inline through a call with vms tates?
Well, you compose the continuations (the basic operation on a
continuation).  This is irrespective of languages -- you just need a
way to compose continuations.  Whether you have that composition for a
pair of langs is impl detial.

So far this is very biased.  what structure can we impose over the vms
continuations?

Well, the normal cont. is equiv. to these under some conditions.  And
we can optimize the normal cont. with the assumption that these are
equiv.



What about CSE? If they don't dominate each other, then you generally
can't, because the continuations that the callee may return to may not
be equivalent.  What happens if they dominate?  That's tricker.

[^philip]: "Deoptimization terminology" <http://www.philipreames.com/Blog/2015/05/20/deoptimization-terminology/>
