---
layout: post
title:  "deoptimization states are delimited continuations"
permalink: deopt-states-are-delim-continuations.html
---

*This post assumes knowledge of some basic vocabulary related to
deoptimization.  The footnotes have some pointers [^deoptintro]
[^deoptv8] [^deoptjvm] on getting started.*

[^deoptintro]: "Deoptimization terminology" <http://www.philipreames.com/Blog/2015/05/20/deoptimization-terminology/>
[^deoptv8]: "Deoptimize me not, v8" <https://blog.indutny.com/a.deoptimize-me-not>
[^deoptjvm]: "The Java HotSpot Performance Engine Architecture: Dynamic Deoptimization" <http://www.oracle.com/technetwork/java/whitepaper-135217.html#dynamic>


Operationally, the "abstract VM state" a side exit or an invalidation
point consumes can be characterized as the "interpreter state" at that
point in the code.  In other words, it is what the interpreter's local
state would look like if the interpreter were executing instead of
optimized code.

Semantically, I think *delimited continuations*[^delim] are the right
way to formalize abstract VM states.  The "limit" of a "VM state
continuation" is the end of the physical frame the potentially
deoptimizing operation (a call or a safepoint poll) is invoked from.
The continuation itself runs in the interpreter, and the VM state
encodes the initial state of the bytecode interpreter as data.  The
act of deoptimizing a frame is then the act of invoking this "VM state
continuation" instead of returning to the normal return address /
stack frame continuation (henceforth referred to as the "normal
continuation").

[^delim]: <https://en.wikipedia.org/wiki/Delimited_continuation>

To kick things off, lets use this view to try to answer a basic
question about VM states -- what happens when we inline through a
potentially deoptimizing call?  To be concrete, lets say that we have

    void f() {
      counter_f++;
      g();  # vm_state = vm_state_a
    }
    
    void g() {
      counter_g++;
      h();  # vm_state = vm_state_b
    }

And you wish to inline `g` into `f`.  What VM state should you feed to
`h` once it is inlined into `f`?

    void f_inlined() {
      counter_f++;
      /* inlined g */
      counter_g++;
      h();  # vm_state = ???
    }

Here we have inlined what would have been two frames, `f` and `g`,
into a single inlined frame, and we need a continuation delimited till
the invocation boundary of `f_inlined`.  Pre-inlining, deoptimizing
the frames individually would involve first executing the `vm_state_b`
continuation (at the call to `h`, in the frame for `g`), and then the
`vm_state_a` continuation (at the call to `g`, in the frame for `f`).
So, to deoptimize the inlined frame, we need to execute the
`vm_state_b` continuation followed by the `vm_state_a` continuation.
In other words, we need a continuation that is the *composition* of
these two continuations!  Just like inlining composes the "normal
return" continuations, it also composes the "VM state" continuations.
The final IR then has to look like:

    void f_inlined() {
      counter_f++;
      /* inlined g */
      counter_g++;
      h();  # vm_state = compose(vm_state_b, vm_state_a)
    }

# structure

Modeling VM states as arbitrary continuations is fairly loose; stating
that a potentially deoptimizing call can return either to the normal
continuation or invoke some other arbitrary continuation still allows
more kinds of behavior than we'd like to have to reason about.  Can we
reign in this definition by imposing some additional structure while
still keeping the formalism useful?  I think we can.

Deoptimization states, as typically used, have some structure in them.
Usually the reason a caller wishes to invoke the deoptimization
continuation instead of the normal continuation is that the
deoptimization continuation can handle cases that normal continuation
cannot.  Moreover, in every state of the system the normal
continuation is a correct implementation of the program being
executed, the deoptimization continuation is semantically equivalent
to the normal continuation.

The language runtime tends to give us some more structure -- it is
responsible for ensuring that a function always returns into the
continuation that is correct given the current state of the world.  So
if a function returns into the normal continuation, $$N$$, then we
know the deoptimization continuation it would have possibly returned
into, $$D$$, is equivalent to $$N$$.  Therefore we can optimize $$N$$
with the assumption that it is equivalent to $$D$$, since the runtime
will not execute $$N$$ otherwise!

Let's look at an example:

    void f() {
      func_a();  # vm_state = vms_a
      // continuation A
      uncommon_trap();  # vm_state = vms_b
      // continuation B
    }

Here `continuation A` is the normal continuation for the call to
`func_a` and `continuation B` is the normal continuation for the call
to `func_b`.  `uncommon_trap` is a special function that
unconditionally invokes the deoptimization continuation, and has no
other side effects.

Since `continuation A` does nothing other thank invoke the
continuation `vms_b` (via the call to `uncommon_trap`), we have
`continuation A` $$\equiv$$ `vms_b`.  However, *within* `continuation
A`, we know that `continuation A` $$\equiv$$ `vms_a`.  Therefore we
can replace the `vms_b` deopt state being passed to `uncommon_trap()`
with `vms_a`, since the call to `uncommon_trap()` is within
`continuation A`.  This property is sometimes phrased as "replaying
from the last valid VM state" and is exploited by some
compilers[^graal].

Note that we haven't proved that `vms_a` is unconditionally equivalent
to `vms_b`.  Can you see why replacing `vms_a` with `vms_b` at
`func_a` will be incorrect?

# conclusion

In concluding, I think delimited continuations form an elegant
semantic model for describing VM states.  In the future I plan to
spend some time trying to come up with optimizations and
simplifications that can be done on VM states as first class objects
based on this interpretation.

[^graal]: Speculation Without Regret: Reducing Deoptimization
    Meta-data in the Graal compiler
    <http://ssw.jku.at/General/Staff/GD/PPPJ-2014-duboscq-29.pdf>
