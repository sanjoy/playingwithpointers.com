---
layout: post
title:  "Reference Counting: Harder than it Sounds"
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

# Problem 0: Stores to the Heap need to be XCHGes

(Edit: I initially had a few mistakes here -- I'd claimed that the
stores need to be CAS'es when an XCHG would be sufficient.  The order
between the increment and the decrement was also incorrect.  Thanks
[@barrkel](https://disqus.com/by/barrkel/) for pointing these out!)

Executing a store to the heap requires incrementing the refcount of
the object stored, and decrementing the refcount of the object
overwritten.  On a single threaded application this can be implemented
in the obvious way as

    old_val = *heap_addr
    *heap_addr = new_val
    Increment_Refcount(new_val->refcount)
    Decrement_Refcount(old_val->refcount)

Naively extending this to a multi-threaded system requires doing a XCHG

    Atomic_Increment_Refcount(new_val)
    old_val = Atomic_XCHG(heap_addr, new_val)
    Atomic_Decrement_Refcount(old_val)

which has a fairly high overhead, especially since the programmer did
not ask for an atomic operation, and the extra synchronization is
purely "dead" overhead.

## Solutions I'm aware of

"An on-the-fly reference counting garbage collector for Java."[^1]
enumerates a solution that involves synchronizing the collector and
the mutator, à la checkpoints[^2] or ragged safepoints[^3].  A
solution like that is feasible in a JVM, but would be difficult to
implement for an uncooperative environment, e.g. for a thread-safe
version of `std::shared_ptr<T>`.

# Problem 1: Racing Increments and Decrements

Consider two threads racing to update a slot in the heap:

    Thread_A:
      val = object->field;
      val->refcount++;  // either because you actually track refs
                        // on the stack or because you're about to
                        // publish val to some slot on the heap

and

    Thread_B:
      ;; Semantically, this is "object.field = null"
      old_val = Atomic_XCHG(&(object->field), null)
      if (--old_val->refcount == 0)
        delete old_val;

There is a race between `Thread_A` and `Thread_B` if the refcount of
the initial value of `object->field` is `1` (i.e. the initial value of
`object->field` is reachable only from `object`):

    Thread_A: val = object->field;
    Thread_B: old_val = Atomic_XCHG(&(object->field), null)
    Thread_B: --old_val->refcount == 0 // == true
    Thread_B: delete old_val;
    Thread_A: val->refcount++; // == CRASH!

In (other) words `Thread_B` just decremented the reference count of an
object `O` because it overwrote a slot in the heap that reached
it. The reference count becomes zero after decrementing, so it knows
that _now_ there are no slots in the heap that point to `O` (and the
slot it overwrote was the *only* slot that contained a pointer to
`O`).  But it still needs to know that there isn't a `Thread_A` that
fetched `O` out of the heap before `Thread_B` overwrote the slot, and
got stalled before it could increment the reference count.  When
`Thread_A` *started* `O` was reachable normally and had a reference
count of `1`; but that is not relevant here.

## Solutions I'm aware of

There are three solutions to this that I'm aware of:

  1. **Hazard pointers**[^4] -- `val->refcount++` in `Thread_A` counts
     (no pun intended!)  as a hazardous access, and could be protected
     by a published hazard pointer.  However, I think there are some
     subtleties here, discussed below.

  2. **Pass the buck**[^5] -- I don't understand this solution quite
     yet, but it looks like a generalization of hazard pointers.

  3. **ThreadScan**[^6] -- this was pointed out to me by
     [@Matt](https://twitter.com/matt_dz/with_replies).  The subtlety
     with hazard pointers mentioned below also applies to ThreadScan,
     as far as I can tell.

These should not be fundamentally difficult to implement in an
uncooperative environment (e.g. for a thread-safe
`std::shared_ptr<T>`), but they're still very tricky to get right.

## A Subtlety with Hazard Pointers

I think there is an issue with using hazard pointers for reference
counting -- a "node" in our "data structure" (the heap) can go from
"unreachable from the heap" to "reachable from the heap".  This means
if we do something like this for `obj.field = null` (in thread `A`,
say):

    // Trying to set obj->field to null
    do {
      old_val = obj->field
      publish_hazard_ptr(old_val)
    } while(CAS(&(object->field), old_val, null) != Success);
    if ((--old_val->refcount) <= 0)
      hazard_ptr_free(old_val)
    clear_hazard_ptr()

then we have a race between another thread (`B`, say) loading
`obj->field` and linking it back to the heap: that operation could
have started before thread `A` unlinked `old_val` from the heap, and
finished before `A` called `hazard_ptr_free`.  Since `B` no longer has
a hazard pointer to `old_val`, `A` would end up freeing something
reachable from the heap.

Note: in this example I've had to use CAS instead of XCHG, since I
need to guarantee that `obj->field` is `old_val` after `old_val` has
been published as a hazard pointer.  There may be a way around this --
I haven't spent too much time thinking about it.

The issue seems solvable though, perhaps we need to be careful to not
increment refcounts of objects with a zero refcount?  That would mean
the increment operation needs to be something like an `xadd` instead
of an `add`.

# Other Solutions

I'm interested in hearing about other solutions to these problems.  If
you're aware of any, please comment here, drop me an email, or
[tweet](https://twitter.com/SCombinator) at me -- I'll update this
section with appropriate credits.

{% hnlink https://news.ycombinator.com/item?id=12152230 %}

[^1]: Levanoni, Yossi, and Erez Petrank. "An on-the-fly reference counting garbage collector for Java." ACM SIGPLAN Notices 36.11 (2001): 367-380.

[^2]: Click, Cliff, Gil Tene, and Michael Wolf. "The pauseless GC algorithm." Proceedings of the 1st ACM/USENIX international conference on Virtual execution environments. ACM, 2005.

[^3]: Pizlo, Filip, et al. "Schism: fragmentation-tolerant real-time garbage collection." ACM Sigplan Notices. Vol. 45. No. 6. ACM, 2010.

[^4]: Michael, Maged M. "Hazard pointers: Safe memory reclamation for lock-free objects." Parallel and Distributed Systems, IEEE Transactions on 15.6 (2004): 491-504.

[^5]: Herlihy, Maurice, Victor Luchangco, and Mark Moir. "The repeat offender problem: a mechanism for supporting dynamic-sized lock-free data structures." (2002).

[^6]: Alistarh, Dan, et al. "ThreadScan: Automatic and Scalable Memory Reclamation." (2015).
