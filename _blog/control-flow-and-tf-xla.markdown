---
layout: post
title:  "Control Flow in TensorFlow & XLA's Auto-Clustering"
keywords: "TensorFlow, XLA"
date: 2018-10-7
---

In this post we'll look at an interesting issue that crops up when auto-clustering TensorFlow graphs.  I've deliberately focused more on the problem than on the solution -- the possible solutions are, in my opinion, fairly obvious once the problem is clear.

# Control flow in TensorFlow

First we need a high level overview of how control flow is represented in TensorFlow graphs.

The canonical reference to control flow in TensorFlow is "Dynamic control flow in large-scale machine learning"[^paper] but we'll do a quick 'n dirty partial overview for this post.

[^paper]: Yu, Y., Abadi, M., Barham, P., Brevdo, E., Burrows, M., Davis, A., Dean, J., Ghemawat, S., Harley, T., Hawkins, P. and Isard, M., 2018, April. Dynamic control flow in large-scale machine learning. In Proceedings of the Thirteenth EuroSys Conference (p. 18). ACM.

## Control Flow in Acyclic Graphs

TensorFlow represents computations as directed graphs where nodes are operations (e.g. matrix multiply) and edges are data flowing between operations (e.g. dense N-dimensional arrays).  Data dependencies constrain the producer to execute before the consumer[^notanir] and there may be control edges between nodes to further constrain their execution order.  TensorFlow operations can have multiple outputs, and can have side effects.

[^notanir]: This may seem insignificant but it means that optimization that break data dependencies, like `A * 0` => `0`, are not generally correct as-is over TensorFlow graphs.

TensorFlow graphs represent control flow via "deadness".  During execution some nodes can be "dead" which, roughly speaking, means they're not executed[^transfernodes].  The vast majority of TensorFlow operations obey the following rules:<a name="deadnessrules"></a>

[^transfernodes]: There are some exceptions to this, but they're not important in the context of this post.

 * A node is dead if *any* if its inputs are dead.
 * If a node is dead, *all* of its outputs are dead.
 * If a node is alive, *all* of its outputs are alive.
 
Terminology: above and elsewhere by "alive" I simply mean "not dead".
 
There are some special operations that break these rules, as otherwise we'll only have trivial control flow:  TensorFlow has a `Switch` operation, which very roughly speaking, fills the role of a "conditional branch", and a `Merge` operation which, again very roughly speaking, is like a "phi" node[^strainedanalogy] [^controltrigger].  In terms of deadness:

[^controltrigger]: There is also a `ControlTrigger` operation that produces a live output irrespective of whether its inputs are dead or not, but it isn't relevant for this post.

[^strainedanalogy]:  This is a very strained analogy for various reasons not relevant to this post.

 * `Switch` takes two inputs: a predicate `pred` and a value `value`.  It has two outputs:
     - If `pred` is false then the first output is dead and the second output is `value`
     - If `pred` is true then the second output is dead and the first output is `value`

   If any of the inputs to the `Switch` itself are dead then all outputs are dead.
 * `Merge` takes `N` inputs and propagates one of the live inputs to its output.  If all the inputs are dead then the `Merge` produces a dead value.
 
For example, an if-then-else diamond that computes `Condition ? (X - 1) : (X + 1)` looks like:

{% graphviz %}
digraph {
  ordering=out;
  Condition -> Switch [label="pred"]
  X -> Switch [label="value"]
  Switch -> "+ 1" [label="F"]
  Switch -> "- 1" [label="T"]
  "- 1" -> Merge
  "+ 1" -> Merge
}
{% endgraphviz %}


## Control Flow in Cyclic Graphs (a.k.a. Loops)

Control flow in cyclic graphs are a straightforward extension of the above: `Merge` no longer needs all of its inputs to have executed before it is executed; it just needs to see one live input which it propagates to its output.  Thus, a simple `for (i = 0; i < 10; i++)` loop looks like this:

{% graphviz %}
digraph {
  ordering=out;
  Zero -> Merge
  Merge -> Add1
  Add1 -> LessThan10
  LessThan10 -> Switch
  Add1 -> Switch
  Switch -> Merge [label="T"]
  Switch -> LoopExit [label="F"]
}
{% endgraphviz %}


In reality things are more complicated because TensorFlow graphs have a concept of "frames", but that's not relevant for this post.

# A Problem with XLA Clusters

XLA is an optimizing compiler for TensorFlow graphs, and one way (but not the *only* way) to use XLA is by having TensorFlow automatically invoke XLA on eligible TensorFlow subgraphs[^notallops].  This involves [replacing these supported subgraphs](https://github.com/tensorflow/tensorflow/blob/d78b3484d4b98790c2d3a7c0d861487e2fcdefdf/tensorflow/compiler/jit/build_xla_launch_ops_pass.cc#L35) with `XlaLaunch`[^lazycompilation] operations which, when executed by the TensorFlow graph executor, JIT compiles the subgraph using XLA and invokes the resultant executable.  This method is called "XLA auto-clustering".

[^notallops]: Not all TensorFlow operations are supported by XLA, so, in general, some parts of the TensorFlow will still have to be executed by TensorFlow.

[^lazycompilation]:  Things are going to get a bit more complicated soon to support "lazy compilation" but this statement will still remain correct in essense.

However, given what we've seen so far, auto-clustering can be problematic for graphs like these:

{% graphviz %}
digraph {
  ordering=out;
  A [shape=box, style=filled, fillcolor=slategray1]
  B [shape=box, style=filled, fillcolor=slategray1]
  C [shape=box, style=filled, fillcolor=slategray1]
  X [shape=box, style=filled, fillcolor=slategray1]
  Y [shape=box, style=filled, fillcolor=slategray1]
  InputA[label="P (Live)"]
  InputB[label="Q (Live)"]
  InputC[label="R (Dead)"]
  OutputA[label="S (Live)"]
  OutputB[label="T (Dead)"]

  InputA -> A
  InputB -> B
  InputC -> C
  A -> X
  B -> X
  B -> Y
  C -> Y
  Y -> OutputB
  X -> OutputA
}
{% endgraphviz %}

Legend: the nodes in blue boxes are all compilable by XLA while the nodes in white ellipses are not.  _A_, _B_, _C_, _X_, _Y_ are "normal" TensorFlow operations that follow the simple [simple deadness propagation rules](#deadnessrules) mentioned above.

If we cluster the nodes _A_, _B_ and _C_ into a single XLA cluster (which feels natural) then the clustered graph will look like this:

{% graphviz %}
digraph {
  "XLA Cluster" [shape=box3d, style=filled, fillcolor=slategray1]
  InputA[label="P (Live)"]
  InputB[label="Q (Live)"]
  InputC[label="R (Dead)"]
  OutputA[label="S (Dead)"]
  OutputB[label="T (Dead)"]
  InputA -> "XLA Cluster"
  InputB -> "XLA Cluster"
  InputC -> "XLA Cluster"
  "XLA Cluster" -> OutputA
  "XLA Cluster" -> OutputB
}
{% endgraphviz %}

In the clustered graph **both** _S_ and _T_ are dead while in the pre-clustered graph only _T_ was dead. This follows directly from the [rules above](#deadnessrules): 

 * In the pre-transform graph all inputs to _A_, _B_ and _X_ are live, and therefore all outputs from _X_ are live.
 * In the post transform graph at least one input to _XLA Cluster_ is dead, and therefore all outputs from _XLA Cluster_ are dead.

This difference in deadness will cause some nodes in the clustered graph to not execute which should have been executed.  In other words this is a miscompile.

# Solution: Static Analysis

There are several ways of fixing this, but perhaps the most straightforward way is via a [static analysis](https://github.com/tensorflow/tensorflow/blob/6619dd5fdcad02f087f5758083e2585bdfef9e78/tensorflow/compiler/jit/deadness_analysis.h) that can prove whether a TensorFlow node can be clustered safely.  This static analysis maps each TensorFlow node to a predicate that is true if and only if the node is alive.  For example, given the following graph, the predicate for _Add_ will be "_P0_ & _P1_":

{% graphviz %}
digraph {
  P0 -> Switch0 [label="pred"]
  P1 -> Switch1 [label="pred"]
  V0 -> Switch0 [label="v"]
  V1 -> Switch1 [label="v"]
  Switch0 -> Add [label="T"]
  Switch1 -> Add [label="T"]
}
{% endgraphviz %}


Using this analysis we only cluster nodes that have identical liveness predicates.  This ensures that all nodes in the cluster are either

 * All dead in the pre-transform graph, in which case it is correct to kill all the outputs from the cluster.
 * All alive in the pre-transform graph, in which case it is correct to propagate a live value to all the outputs from the cluster.

Comparing liveness predicates is necessarily conservative -- the "leaves" of the predicates can be symbolic (so predicates can't always be simplified to True or False) which makes comparing predicates NP-complete[^npcomplete].

For simplicity we implement the "all nodes have identical liveness" check a little differently -- we implement it as "avoid clustering nodes that have inputs with possibly mismatching liveness".  This is equivalent to "all nodes have identical liveness" because XLA clusters are connected (but not strongly connected) and XLA does not support control flow operations like `Switch` and `Merge`.

[^npcomplete]:  We can translate a 3SAT problem into the question "Can node X and node Y be clustered together" where X has a predicate equivalent the 3SAT formula and Y has the trivial predicate "True".

