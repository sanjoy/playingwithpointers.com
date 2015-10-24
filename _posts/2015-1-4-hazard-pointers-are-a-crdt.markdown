---
layout: post
title:  "hazard pointers are a CRDT"
permalink: hazard-pointers-are-a-crdt.html
keywords: "hazard pointers, crdt"
---

I recently watched an excellent video by Marc Shapiro on conflict-free
replicated data types[^shapiro] (usually abbreviated as *CRDT*); and I
think I may have spotted connection between CRDTs and hazard pointers.
My understanding of CRDTs is very "fresh" (just that one video) so
take this with a grain of salt.

[^shapiro]: "Strong Eventual Consistency and Conflict-free Replicated
    Data Types" <https://www.youtube.com/watch?v=ebWVLVhiaiY>

# what are CRDTs?

My current understanding of a CRDT is rather naive; but from what I've
grasped so far, a CRDT is essentially a "normal" data structure
modeled as a semilattice.  With that done (*if* it can be done), the
lattice's merge operation can be used to "integrate" information
received from different processes in a well-defined way (this is the
"conflict-free replicated" part).  I've already mentioned the video by
Marc Shapiro [^shapiro], I think that is a good starting point.
Another interesting collection of links can be found at "Readings in
conflict-free replicated data types" [^readinglist] but I have not
gone through any of them so far.

[^readinglist]: "Readings in conflict-free replicated data types"
    <http://christophermeiklejohn.com/crdt/2014/07/22/readings-in-crdts.html>

On a personal level I like the fact that the role of a semilattice in
a CRDT is very similar to its role in optimizing compilers.

# the problem

The problem we have to solve is this (explained using an example of a
binary tree, but applies to any data structure): say a thread running
a `deleteValue` operation on a lock free binary tree[^btreenote] has
just unlinked a node `n` (so that it is no longer reachable from the
tree's root).  Now it needs to `free` the node `n` to not leak memory,
but before it can do so it needs to be sure that no other threads are
currently using it.  Since this we're talking about a lock-free binary
tree, ensuring this is non-trivial -- it is possible that a thread is
stalled in the midst of traversing the tree, for instance.

[^btreenote]: just to note in case I gave off the wrong impression,
    I'm being slightly flippant here -- lock free binary trees (or
    lock free versions of any non-trivial data structure) are **hard**
    and figuring out how and when to free memory is certainly not the
    only challenge in implementing one.

# what are hazard pointers?

"Hazard pointers" is a pattern that can be used to teach certain lock
free data structures to safely recycle memory (think `malloc` and
`free`) in a non-GC'ed environment, and as a side effect get rid of
the ABA problem in some cases.  Hazard pointers is described in the
paper "Hazard Pointers: Safe Memory Reclamation for Lock-Free Objects"
[^hzrdptrs] (and possibly others).

[^hzrdptrs]: Michael, Maged M. "Hazard pointers: Safe memory reclamation for lock-free objects." Parallel and Distributed Systems, IEEE Transactions on 15.6 (2004): 491-504.

## how they solve the problem

Continuing our example of a `deleteValue` operation on a lock-free
binary tree, once the node `n` has been unlinked from the binary tree,
the deleting thread needs to decide that no thread is (stalled) in a
position where deleting that node will be a problem.  Hazard pointers
gets threads to "publish" a set of "hazardous pointers".  Pointers a
thread is currently accessing are put in this set and they are removed
from this set once the thread is done with them.  Deleting a node is a
problem only if it is in the hazardous set published by some thread,
and only a node reachable from the root of the binary tree (not yet
unlinked) can go from being not hazardous to being hazardous.  In our
example, the thread running `deleteValue` knows that `n` can be safely
`free`ed if it is not present in any other thread's hazardous pointer
set.  If it is present in another thread's hazardous pointer set, it
waits till that is no longer true.

# squinting hazard pointers into CRDTs

In a message-passing context, hazard pointers can be seen as threads
"agreeing" that they are "okay" with the deletion of some node.  This
is a per node property and can be modeled as a map mapping nodes (node
ID's or pointers) to sets of threads.  Since we don't care about
removing threads from sets (once a thread has agreed that it is okay
to delete a specific node, it cannot go back to disagreeing), the set
used to hold threads can be made add-only.

If we denote with $$M[p]$$ the set of threads $$p$$ maps to (for a
$$p$$ not present in $$M$$, $$M[p]$$ is $$\emptyset$$) and let
$$dom(M)$$ be the domain (set of keys) for the map $$M$$, then the
merge function can be defined as follows:

$$M_i \wedge M_j = \left\{\left(p, M_i[p] \cup M_j[p]\right) : p \in (dom(M_i) \cup dom(M_j))\right\}$$

In words, the set of threads okay with deleting $$p$$ according to
$$M_i \wedge M_j$$ is the union of the set of threads okay with
deleting $$p$$ according to $$M_i$$ and $$M_j$$ separately.

Every thread maintains a set of hazard pointers as usual, except now
receiving a new map or removing a pointer from a set of hazard
pointers generates an event -- the thread computes $$M_{new}$$ from
$$M_{old}$$ (its internal view of the world) and broadcasts that to
every other thread:

$$M_{new} = \left\{\left(p, M_{old}[p] \cup \{t_{self}\} \right) : p \in \left(dom(M_{old}) - H\right)\right)\}$$

where $$t_{self}$$ is the thread ID of the thread generating the
event.  Intuitively, this $$t_{self}$$ "agreeing" that it is "okay" to
delete $$p$$ if $$p$$ is not in its hazardous pointer set.

In this scheme, to delete a node, the deleting thread adds $$\left(p,
t_{deleter}\right)$$ to its version of $$M$$ and broadcasts the same.
It is okay to delete $$p$$ as soon as its version of $$M[p]$$ contains
every thread.

# conclusions

## practical aspects

I will not even pretend that this has practical uses.  Even if this
could be implemented, I'd expect this to be orders of magnitude slower
than a good implementation of hazard pointers.  I have not tried to
generalize this to threads startup and destruction.

## the object graph approach

Another possible approach and why it does not work: use graphs to
abstractly describe the state of the heap, and use a CRDT to represent
that graph.  It is okay to delete a node if there is no path from some
thread's stack to that node.  However it is possible that some thread
indeed has a route to the to-be-deleted pointer, it is just that the
deleting thread's version of the object graph does not reflect that
yet and will not reflect that till some arbitrary point of time in the
future.  In the scheme described in this post, you know you're safe to
delete $$p$$ as soon as all threads have agreed that it is okay to do
so.  In the graph scheme, there is no such point in time since changes
in the object graph can take an arbitrary amount of time to propagate
to a given thread's local view.
