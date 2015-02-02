---
layout: post
title:  "interference graphs for SSA are chordal"
permalink: ssa-interference-chordal.html
---

# background & context

I ran into a very interesting idea a couple of weeks back: if you're
working with pure SSA (phi nodes and all) then you get to do optimal
register allocation in polynomial time.  You don't get a free lunch
though, because you will eventually have to translate out of SSA by
mapping the phi nodes into copies; and doing that optimally is NP
complete[^outofssa].

Please note that **none of this is original work** and optimal
register allocation using SSA is a well-researched topic.  A set of
references can be found in the [bibliography section](#bib).

[^outofssa]: supposedly established in "Optimizing Translation Out of
    SSA Using Renaming Constraints"
    <https://dl.acm.org/citation.cfm?id=977678>, but I have not read
    that paper.

The key observation that allows this is that the interference
graph[^igraph] you get from an SSA program[^ssa] is a chordal
graph[^chordal], and chordal graphs can be optimally colored in
$$O\left(|V| + |E|\right)$$ time.  There are many ways to prove this,
and one such way is presented here.

[^igraph]: <https://lambda.uta.edu/cse5317/fall02/notes/node37.html>
[^ssa]: <http://www.wikiwand.com/en/Static_single_assignment_form>
[^chordal]: <http://www.wikiwand.com/en/Chordal_graph>
[^chordalfrench]: I don't read French, but it is possible that
    "Register allocation and spill complexity under SSA"
    <http://www.ens-lyon.fr/LIP/Pub/Rapports/RR/RR2005/RR2005-33.pdf>
    contains the same proof.

# proof

## what are chordal graphs?

A graph is chordal if every cycle of length > 3 has a chord.  Any
(induced) subgraph of a chordal graph is again a chordal graph: if the
vertices of the subgraph induce a cycle, they would also induce the
chords present in the original chordal graph.  Chordal graphs are
useful because they are perfectly orderable[^ordereable] -- perfectly
orderable graphs can be colored in polynomial time.

[^ordereable]: <http://www.wikiwand.com/en/Perfectly_orderable_graph>

## the intersection graph of connected subgraphs of a tree

In "The intersection graphs of subtrees in trees are exactly the
chordal graphs" Gavril[^subtreeproof] completely characterizes chordal
graphs as intereference graphs of subtrees of topological
graphs[^topograph].  We do not need the full treatment of topological
graphs since for our purposes it is sufficient to show that certain
kinds of graphs are chordal (and not the other way around).  So we'll
go for a restricted and simpler "proof" (essentially a simplified form
of Gavril's proof) that works with "normal" edge-vertex graphs.

Consider a tree $$T$$.  We construct a graph $$G$$ such that the
vertices of that graph $$V(G)$$ are connected subgraphs of $$T$$ and
two vertices $$n_1$$ and $$n_2$$ have an edge between them if the
subtrees they correspond to are not disjoint ($$n_1 \cap n_2 \neq
\emptyset$$).  Then $$G$$ is a chordal graph.

This construction of having sets as vertices, and edges between two
vertices iff their intersection is non-empty is called an
"intersection graph". Another way of stating our assertion is
"intersection graphs of connected subtrees of a tree are chordal"

[^topograph]: <http://www.wikiwand.com/en/Topological_graph>

I won't present a full proof here, but a small example (that can be
extended into a proof) to motivate why the statement above should be
true.

![Inf graph](assets/interference-graph.png)

Assume $$G$$ (the intersection graph of connected subtrees of a tree,
$$T$$) has a cycle of length 4 without a chord.  Each of the edges,
$$p_i$$ correspond to a non-empty set of nodes in $$T$$.  We know that
every vertex in $$p1 \cup p2$$ belongs to the connected subtree
corresponding to $$v2$$.  This means $$\forall n_{1} \in p1, \forall
n_{2} \in p2$$ there is a acyclic path between $$n_{1}$$ and $$n_{2}$$
in $$v2$$.  Same is true for $$\forall n_{2} \in p2, \forall n_{3} \in
p3$$ (the paths connecting these are in $$v3$$) and so on.  Therefore,
we can pick $$n_0 \in p0$$, $$n_1 \in p1$$, $$n_2 \in p2$$ and $$n_3
\in p3$$ such that there is a path $$n_0 \leftrightarrow n_1
\leftrightarrow n_2 \leftrightarrow n_3 \leftrightarrow n_0$$.  We
will prove that the shortest of these paths is a cycle (i.e. has no
repeated vertices), hence any tree containing $$v0$$, $$v1$$, $$v2$$
and $$v3$$ has a cycle.  Since trees don't contain cycles, we'll have
proved by contradiction that the above construct could *not* have been
the intersection graph of connected subtrees of a tree.  Hence all
cycles of length 4 in an intersection graph of connected subtrees of a
tree will have a chord.  A full proof of the assertion can be
constructed by extending this argument to cycles of length greater
than 4; and a yet more general proof can be found in Gavril's
paper[^subtreeproof] as mentioned earlier.

To prove that the path $$n_0 \leftrightarrow n_1 \leftrightarrow n_2
\leftrightarrow n_3 \leftrightarrow n_0$$ has no repeated vertices
(and hence is a cycle), first note that the path $$n_0 \leftrightarrow
n_1$$ and $$n_2 \leftrightarrow n_3$$ are disjoint, as otherwise
$$v1$$ and $$v3$$ would have a vertex in common and hence this 4-cycle
would have had a chord between $$v1$$ and $$v3$$.  $$n_1
\leftrightarrow n_2$$ and $$n_3 \leftrightarrow n_0$$ are disjoint for
the same reason.  Therefore the only possible repeated vertex will
have to appear in a path connecting two vertices $$n_i$$ and
$$n_{(i+1) \% 4}$$.  Let that repeated vertex be $$n_r$$, making the
path between $$n_i$$ and $$n_{(i+1) \% 4}$$ of the form $$n_i
\leftrightarrow P_0 \leftrightarrow n_r \leftrightarrow P_1
\leftrightarrow n_r \leftrightarrow P_2 \leftrightarrow n_{(i+1) \%
4}$$ where $$P_i$$ are paths themselves.  But this means that there is
a shorter path between $$n_i$$ and $$n_{(i+1) \% 4}$$, $$n_i
\leftrightarrow P_0 \leftrightarrow n_r \leftrightarrow P_2
\leftrightarrow n_{(i+1) \% 4}$$, also contained in $$v(i+1\%4)$$.
Therefore $$n_0 \leftrightarrow n_1 \leftrightarrow n_2
\leftrightarrow n_3 \leftrightarrow n_0$$ is not the shortest path for
the given $$n_0 \in p0$$, $$n_1 \in p1$$, $$n_2 \in p2$$ and $$n_3 \in
p3$$.  Hence in the shortest possible $$n_0 \leftrightarrow n_1
\leftrightarrow n_2 \leftrightarrow n_3 \leftrightarrow n_0$$ there
can be no such repetition; and such a shortest path is a cycle.

## dominator trees and chordal graphs

Consider the dominator tree graph[^domtree] of the SSA program being
register allocated (with the tree denoting the usual "use dominates
def" relation).  The live range of a def is the union of all paths
from that def to any use of that def[^reachable].  We denote such a
path as the set of SSA instructions that would be executed if the
program follows that control flow, including the def but excluding the
use.  Thus each live range corresponds to a subset of the dominator
tree (where each vertex is an SSA instruction).  If we can show that a
live range corresponds to a *connected subtree* of the dominator tree,
we can use the result from the previous section to state that the
interference graph of the program being register allocated is chordal
(since it is the intersection graph with connected subtrees as
vertices) and can be colored in polynomial time.  Note that while a
dominator tree is semantically a directed tree we don't need to use
that additional structure to invoke the above result.

[^reachable]: This is assuming that the def is reachable from the
    entry of the control flow graph.  We do not consider unreachable
    (dead) defs to keep the discussion simple.

To show that the live range of an SSA value is always a connected
subtree, we exploit two properties of SSA values:

 1. the live range of a def only contains instructions it dominates.
    If it contained an instruction it does not dominate, then by the
    definition of a live range, we've discovered a path from a def to
    a use that contains an instruction the def does not dominate.
    This means there is a path form the entry of the control flow
    graph to the use that does not contain the def.  This means the
    def does not dominate one of its uses, and this cannot happen in a
    well-structured SSA control flow graph.

 2. if the live range of a def $$D$$ contains $$L_{end}$$ and there is
    an SSA instruction $$L_{middle}$$ such that $$L_{middle}$$
    dominates $$L_{end}$$ then the live range of $$D$$ contains
    $$L_{middle}$$.  This is true since every path from $$D$$ to
    $$L_{end}$$ contains $$L_{middle}$$.

(1) tells us that the live range of a def when represented in the
dominator tree is a subset of the section of the dominator tree rooted
at def.  (2) tells us that this subset is really a connected subtree
-- every instruction in the path leading down from the def to an
instruction contained in the def's live range belongs to the def's
live range.

# conclusion

There is an existing compiler IR that uses chordality of SSA's
interference graphs to do optimal register allocation: libFirm
<http://pp.ipd.kit.edu/firm/>.  I'd like to spend some time looking
at that next.

# bibliography<a name="bib"></a>

 * "Optimal Register Sharing for High-Level Synthesis of SSA Form
Programs"
<http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.61.6569>

 * Sebastian Hack's PhD thesis:
   <http://digbib.ubka.uni-karlsruhe.de/volltexte/documents/6532>

 * "SSA-based Register Allocation" <http://www.cdl.uni-saarland.de/projects/ssara/>

 * libFirm has an SSA-based register allocator <http://pp.ipd.kit.edu/firm/>

[^domtree]: <http://www.wikiwand.com/en/Dominator_(graph_theory)>

[^subtreeproof]: "The intersection graphs of subtrees in trees are
    exactly the chordal graphs"
    <http://www.sciencedirect.com/science/article/pii/009589567490094X>
