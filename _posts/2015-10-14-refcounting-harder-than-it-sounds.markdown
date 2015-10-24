---
layout: post
title:  "reference counting: harder than it sounds"
permalink: refcounting-harder-than-it-sounds.html
keywords: "reference counting, gc, garbage collection, language runtimes, shared_ptr"
---

Naive reference counting is "easy" to implement on a system that does
not share objects between threads, but thinking about reference
counting in systems that **do** share objects between threads, two
problems (other than the standard "increments and decrements need to
be atomic operations") come to mind.  So far the contents of this post
(which are **not** novel) have lived in one-off tweets and emails, but
I think it is time to write them down in an organized way.

# problem 0: stores to the heap need to be CASes

Executing a store to the heap requires incrementing the refcount of
the object stored, and decrementing the refcount of the object
overwritten.  On a single threaded application this can be implemented
in the obvious way as

    old_val = *heap_addr
    *heap_addr = new_val
    Decrement_Refcount(old_val->refcount)
    Increment_Refcount(new_val->refcount)

Naively extending this to a multi-threaded system requires doing a CAS

    do {
      old_val = *heap_addr
    } while (CAS(heap_addr, old_val, new_val) != Success);
    Atomic_Decrement_Refcount(old_val->refcount)
    Atomic_Increment_Refcount(new_val->refcount)

which has a fairly high overhead, especially since the programmer did
not ask for an atomic operation, and the extra synchronization is
purely "dead" overhead.

## solutions I'm aware of

"An on-the-fly reference counting garbage collector for Java."[^1]
enumerates a solution that involves synchronizing the collector and
the mutator, à la checkpoints[^2] or ragged safepoints[^3].  A
solution like is feasible in a JVM, but would be difficult to
implement for an uncooperative environment, e.g. for a thread-safe
version of `std::shared_ptr<T>`.

# problem 1: racing increments and decrements

Consider two threads racing to update a slot in the heap:

    Thread_A:
      val = object->field;
      val->refcount++;  // either because you actually track refs
                        // on the stack or because you're about to
                        // publish val to some slot on the heap

and

    Thread_B:
      ;; Semantically, this is "object.field = null"
      do {
        old_val = object->field
      } while (CAS(&(object->field), old_val, null) != Success);
      if (--old_val->refcount == 0)
        delete old_val;

There is a race between `Thread_A` and `Thread_B` if the refcount of
the initial value of `object->field` is `1` (i.e. the initial value of
`object->field` is reachable only from `object`):

    Thread_A: val = object->field;
    Thread_B: old_val = object->field
    Thread_B: CAS(&(object->field), old_val, null) // == Success
    Thread_B: --old_val->refcount == 0 // == true
    Thread_B: delete old_val;
    Thread_A: val->refcount++; // == CRASH!

## solutions I'm aware of

There are two solutions to this that I'm aware of:

  1. **Hazard pointers**[^4] -- `val->refcount++` in `Thread_A` counts
     (no pun intended!)  as a hazardous access, and should be
     protected by a published hazard pointer.

  2. **Pass the buck**[^5] -- I don't understand this solution quite
     yet, but it looks like a generalization of hazard pointers.

These should not be fundamentally difficult to implement in an
uncooperative environment (e.g. for a thread-safe
`std::shared_ptr<T>`), but they're still very tricky to get right.

# other solutions

I'm interested in hearing about other solutions to these problems
people have come up with.  If you're aware of any, please comment here
and / or drop me an email -- I'll update this section with appropriate
credits.

[^1]: Levanoni, Yossi, and Erez Petrank. "An on-the-fly reference counting garbage collector for Java." ACM SIGPLAN Notices 36.11 (2001): 367-380.

[^2]: Click, Cliff, Gil Tene, and Michael Wolf. "The pauseless GC algorithm." Proceedings of the 1st ACM/USENIX international conference on Virtual execution environments. ACM, 2005.

[^3]: Pizlo, Filip, et al. "Schism: fragmentation-tolerant real-time garbage collection." ACM Sigplan Notices. Vol. 45. No. 6. ACM, 2010.

[^4]: Michael, Maged M. "Hazard pointers: Safe memory reclamation for lock-free objects." Parallel and Distributed Systems, IEEE Transactions on 15.6 (2004): 491-504.

[^5]: Herlihy, Maurice, Victor Luchangco, and Mark Moir. "The repeat offender problem: a mechanism for supporting dynamic-sized lock-free data structures." (2002).