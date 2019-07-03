---
layout: post
title:  "Auto-Clustering Resource Variable Operations in TensorFlow/XLA"
keywords: "TensorFlow, XLA"
needsMathJAX: False
date: 2019-6-21
---

In this post we will look at how we auto-cluster resource variable operations in TensorFlow graphs into XLA computations and why it isn't entirely trivial.

# A Word About Tensors

Tensors in TensorFlow are represented as instances (surprise!) of the `Tensor` [class](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/framework/tensor.h#L58).  `Tensor` instances contain information about the shape of a tensor and a pointer to a reference counted buffer, which is an instance of  `TensorBuffer`.  Multiple instance of `Tensor` can point to the same `TensorBuffer`.

Conceptually `Tensor`s are immutable[^refvar0], but TensorFlow will opportunistically operate on `Tensor`s "in-place" when it can prove that that's safe.

[^refvar0]: TensorFlow used to have "ref" Tensors that were mutable but ref tensors are deprecated.

# Resource Variables

Resource variables are mutable "cells" that contain a `Tensor`.  The execution model of resource variables is fairly straightforward -- there are three key operations:

 - [`VarHandleOp`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L78) with signature (roughly speaking) `DT_STRING -> DT_RESOURCE`.  It creates a resource variable from a name (which is the string) and the resource variable it creates is represented in the TensorFlow graph as a rank 0 tensor of type `DT_RESOURCE`.
 
 - [`ReadVariableOp`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L133) with signature `DT_RESOURCE -> T`.  It reads the value stored in the resource variable passed as an argument and produces a regular `Tensor`.
 
 - [`AssignVariableOp`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L194) with signature `(T, DT_RESOURCE) -> void`.  It stores its first argument into the resource variable passed in as the second argument.
 
 - There are some operations that "fuse" a resource read or a resource write with some other operation like [`ResourceGather`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L236) and [`ResourceScatter*`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L339).  These can be semantically treated as just reads or writes; they mainly exist to reduce memory consumption.

 - There are some operations like [`AssignAddVariableOp`](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/core/ops/resource_variable_ops.cc#L200) that do both a read and a write.
 
These operations read and write *whole* `Tensor`s at once.  So in no case will TF operations see racing writes being made to an input `Tensor` by some other operation running concurrently[^refvar1].

[^refvar1]: This used to be a problem with legacy reference variables, but they're deprecated now.

The behavior of these resource variable operations is decided by the ["Concurrency Semantics For TensorFlow Resource Variables" RFC](https://github.com/tensorflow/community/blob/master/rfcs/20190610-resource-variable-semantics.md).  The TL;DR of the RFC is:

 - Operations behave _as if_ they were executed in some total order consistent with the partial ordering constraints enforced by the graph.
 
 - Operations like `AssignAddVariableOp` that do a read and a write **do not** do the read and the write as a single atomic operation.
 
The second point means we do not have to separately model ops like `AssignAddVariableOp`.  We can instead mentally "expand" them to a (read, compute, write) triple.

# XLA Clusters ♥ Resource Variables (sort of)

XLA is an optimizing compiler for TensorFlow graphs, and one way to use XLA is by having TensorFlow automatically invoke XLA on eligible TensorFlow subgraphs. This involves replacing these supported subgraphs with `_XlaCompile` and `_XlaRun` operations which, when executed by the TensorFlow graph executor, JIT compiles the subgraph using XLA and invokes the resultant executable respectively. This method is called "XLA auto-clustering".

To maximize optimization opportunities, we'd like the XLA clusters to be as large as possible, and include resource variable operations in XLA clusters whenever possible.  However, XLA's intermediate representation does not have operations that read from and write to resource variables.  So we support resource variables in a somewhat roundabout manner:

 - All resource variables touched by an XLA cluster are "snapshotted" into SSA values when we start executing an XLA cluster.  This is done [in the TF/XLA bridge](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/compiler/jit/xla_launch_util.cc#L150) so it does not matter that XLA does support resource variables.
 
 - The XLA program is executed as a side-effect-free function on the *initial* values of the resource variables to produce *final* values of each resource variable.  XLA does not really know that these SSA values are resource variables; to XLA they just look like regular inputs and outputs.
 
 - The final values produced by the XLA program is written back to the resource variables by [the TF/XLA bridge](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/compiler/jit/xla_launch_util.cc#L369).  Again, since this happens in the bridge, XLA can remain blissfully unaware of resource variables.
 
For instance, consider the following graph (we've abbreviated `VarHandleOp`, `ReadVariableOp` and `AssignVariableOp` to `Var`, `Read` and `Assign` respectively):

{% graphviz %}
digraph {
  graph[bgcolor=gray98,compound=true]
  node[shape=box,fillcolor=azure, style="filled,rounded"]

  V0 [label="v0 = Var('var_0')"]
  V1 [label="v1 = Var('var_1')"]
  R0 [label="r0 = Read(v0)"]
  W0 [label="Assign(v0, 42)"]
  R1 [label="r1 = Read(v0)"]
  Add [label="r2 = r1 + 1"]
  W1 [label="Assign(v0, r2)"]
  W2 [label="Assign(v1, r0)"]
  
  V0 -> R0
  V0 -> R1
  W0 -> R1 [style=dashed]
  R1 -> Add
  Add -> W1
  V0 -> W0
  V0 -> W1
  R0 -> W0 [style=dashed]
  R0 -> W2
  V1 -> W2

  _SOURCE -> V0 [style=dashed]
  _SOURCE -> V1 [style=dashed]
  W0 -> _SINK [style=dashed]
  W1 -> _SINK [style=dashed]
  W2 -> _SINK [style=dashed]
}
{% endgraphviz %}

Let's say we pick the following serialized execution order when compiling the graph with XLA:

```
v0 = Var('var_0')
v1 = Var('var_1')
r0 = Read(v0)
Assign(v0, 42)
r1 = Read(v0)
r2 = r1 + 1
Assign(v0, r2)
Assign(v1, r0)
```

We will effectively transform this to:

```
// Initial reads:
v0 = Var('var_0')
v1 = Var('var_1')
v0_ssa_0 = Read(v0)

// Pure computation:
r0 = v0_ssa_0  // Was: r0 = Read(v0)
v0_ssa_1 = 42  // Was: Assign(v0, 42)
r1 = v0_ssa_1  // Was: r1 = Read(v0)
r2 = r1 + 1    // Was: r2 = r1 + 1
v0_ssa_2 = r2  // Was: Assign(v0, r2)
v1_ssa_0 = r0  // Was: Assign(v1, r0)

// Final writes:
Assign(v0, v0_ssa_2)
Assign(v1, v1_ssa_0)
```

(This is just a simplified form of [SSA conversion](https://en.wikipedia.org/wiki/Static_single_assignment_form#Converting_to_SSA).)

As stated above, the initial reads and the final writes are handled in the TF/XLA bridge while the middle "pure" computation is handled in XLA.

## The Problem

Unfortunately, applying this trick indiscriminately can break the TensorFlow memory model.  For instance, consider the following graph:

{% graphviz %}
digraph {
  graph[bgcolor=gray98,compound=true]
  node[shape=box,fillcolor=azure, style="filled,rounded"]

  StoreX6[label="Assign(v0, 6)",fillcolor=coral]
  LoadY[label="r0 = Read(v1)",fillcolor=coral]

  StoreY[label="Assign(v1, 8)"]
  StoreX7[label="Assign(v0, 7)"]

  SOURCE -> StoreX6[style=dashed]
  StoreX6 -> LoadY[style=dashed]
  LoadY -> SINK[style=dashed]

  SOURCE -> StoreY[style=dashed]
  StoreY -> StoreX7[style=dashed]
  StoreX7 -> SINK[style=dashed]
}
{% endgraphviz %}

After executing the graph the following invariant holds:  **if** `v0` contains `6` **then** `r0` must be `8`.  This holds because if `v0` is `6` then the total order must have had `Assign(v0, 6)` *after* `Assign(v0, 7)`, which puts `r0 = Read(v1)` *after* `Assign(v1, 8)`.

Now putting `Assign(v0, 6)` and `r0 = Read(v1)` in the same XLA cluster is equivalent to rewriting the graph into:

{% graphviz %}
digraph {
  graph[bgcolor=gray98,compound=true]
  node[shape=box,fillcolor=azure, style="filled,rounded"]

  subgraph cluster_1 {
    Prologue[label="v1_ssa = Read(v1) .. (0)"]
    Epilogue[label="Assign(v0, v0_ssa) .. (3)"]
    subgraph cluster_0 {
      node[fillcolor=coral]
      StoreX6[label="v0_ssa = 6"]
      LoadY[label="r0 = v1_ssa"]
    }
  }

  StoreY[label="Assign(v1, 8) .. (1)"]
  StoreX7[label="Assign(v0, 7).. (2)"]

  SOURCE -> Prologue[style=dashed]
  Prologue -> StoreX6[style=dashed]
  StoreX6 -> LoadY[style=dashed]
  LoadY -> Epilogue[style=dashed]
  Epilogue -> SINK[style=dashed]

  SOURCE -> StoreY[style=dashed]
  StoreY -> StoreX7[style=dashed]
  StoreX7 -> SINK[style=dashed]
}
{% endgraphviz %}

But this transformed graph allows `*v0` `==` `6` `&&` `r0` `!=` `8` since the total order could have been `(0)`, `(1)`, `(2)`, `(3)`.

## The Solution

The core of the problem is that even though XLA clusters support resource variable operations [^indirect], they do not support putting certain kinds of (transitive) dependencies between pairs of resource variable operations in the same cluster.

In particular XLA does not support write → read dependencies.  This is because all reads happen at the beginning of cluster execution and all writes happen after cluster execution and there is no way to make a write happen before a read.

Read → write dependencies are fine. All reads happen before all writes so this ordering constraint is trivially satisfied.

Read → read and write → write dependencies are more interesting.  Based on what we've said so far, it should look like they're unsupported too since the TF/XLA bridge does not do the initial reads or the final writes in any particular order.  However, the bridge does all the reads in one atomic operation and all the writes in another atomic operation[^atomic].  This atomicity satisfies read → read and write → write dependencies.

So to ensure that XLA auto-clustering is a semantic preserving operation, we run a [static analysis](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/compiler/jit/resource_operation_safety_analysis.cc) that decides which pairs of resource variable operations have an unsupported (possibly transitive) dependency.  The auto-clustering algorithm uses the result of this static analysis to [make sure](https://github.com/tensorflow/tensorflow/blob/a0a971bcda3dc2fc2fdcae0a29d5a53f82e6d64f/tensorflow/compiler/jit/mark_for_compilation_pass.cc#L1287) that these "incompatible" resource operation pairs are not put in the same cluster.

[^indirect]: Not *directly* but via SSA conversion and co-operation with the TF/XLA bridge as mentioned above.

[^atomic]: This is possible because each resource variable is guarded by a mutex.
