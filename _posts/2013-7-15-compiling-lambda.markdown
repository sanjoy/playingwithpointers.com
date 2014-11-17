---
layout: post
title:  "echoes: compiling λ"
permalink: compiling-lambda.html
---

I've been toying with the idea of writing a compiler for the untyped
lambda calculus [^1] for a while; and now that I'm on vacation, I
finally managed to refactor out some time to spend on it. The first
iteration, `echoes` [^2], generates horrible, but runnable code. It
reads λ expressions (via a lispy syntax) and compiles them to plain
ol' x86-64 assembly, runnable pending getting linked into the
runtime. It understands a tiny bit more than pure lambda calculus --
echoes has native support for booleans, integers and if
statements. The compiled code obeys lazy call-by-name [^3] semantics.

A source term (a closed term in lambda calculus + integers and
booleans) goes through the following phases:

  1. Lambda lifting -- closures are eliminated by passing in explicit
     arguments for each closed variable. λ x. λ y. x + y gets lifted
     into λ x. (λ y x. x + y) x, for example. This allows echoes to
     lift the inner λ y x. x + y out of the function. Note that
     support for currying is still needed, which the runtime provides.

  2. Conversion to HIR -- HIR is a "high-level intermediate
     representation" that the (lifted) lambda functions are compiled
     to. HIR is an SSA based representation that is created and
     manipulated using the Hoopl framework. After its creation, and
     some basic DFA-based optimization (made rather easy by Hoopl and
     the high level nature of HIR), it is lowered to LIR.

  3. Lowering HIR to LIR — LIR is a "low-level intermediate
     representation" that HIR flow graph is lowered to. LIR too is an
     SSA based representation based around the constraint that each
     LIR instruction should be "easily" compilable to a (list of)
     machine instruction(s), for some loose definition of "easily". As
     an example, forcing a value (causing a method invocation if the
     value was a lazy thunk) is done by `ForceHN` in HIR, but is a
     subgraph in LIR that checks if the value to be forced actually
     needs forcing before calling into the runtime. Echoes doesn't
     have a proper register allocator, a "null" register allocator is
     run that simply spills each virtual register to a stack slot and
     inserts appropriate loads and stores.

  4. LIR to x86 -- almost by design, each LIR instruction can be
     lowered into a bunch of x86 instructions without much
     hassle. This is then serialized into a list of strings and
     written out to a `.S` file, which can then by linked to the
     runtime.

  5. The Runtime -- the runtime provides a bunch of functions that
     allow a compiled program to allocate memory and "force" values. I
     haven't written a GC yet (that should be an interesting, separate
     project on its own) and right now programs just leak all their
     memory.

The project [^2] consists of around 1500 lines of Haskell (for the
compiler) and around 200 lines of C / assembly (for the runtime).

# currying and forcing

Each value encountered by a running program is either an integer, a
boolean, or a partially or fully applied function. The lower two bits
of each value are tagged and the semantic value is stored directly
(unboxed) in the higher bits for integers and booleans.

Partially applied functions (called closures in the code-base) are
represented by linked lists. The last node of such lists have the type
`clsr_base_node_t` (a `struct` defined in `Runtime/runtime.h`) with
the layout

    ++++++++++++++++++++++++++++++++++
    |               |                |
    | Code Pointer  | Argument count |
    |               |                |
    ++++++++++++++++++++++++++++++++++

The `Code Pointer` field points to the (compiled) out-of-line function
that implements this closure. The `Argument Count` slot holds the
number of arguments accepted by that code pointer. Other nodes (typed
as `clsr_app_node_t` in C) of this linked list have the layout

    ++++++++++++++++++++++++++++++++++++++++++++
    |              |                |          |
    | Next Pointer | Arguments left | Argument |
    |              |                |          |
    ++++++++++++++++++++++++++++++++++++++++++++

The `Next Pointer` is the usual next field in a linked
list. `Arguments Left` is the number of arguments that can be further
applied to this partially applied function. A `clsr_app_node_t` with
`Arguments Left` set to `0` is fully saturated, and applying any more
arguments to it will result in a runtime error; it can only be
"forced". The `Argument` field holds the argument that was applied to
construct the `clsr_app_node_t`. For instance, the expression `f x y`
will be represented as (assuming `f` is an out-of-line function with
arity 2):

    +++++     +++++     +++++
    | *-|---> | *-|---> | f |
    +++++     +++++     +++++
    | 0 |     | 1 |     | 2 |
    +++++     +++++     +++++
    | y |     | x |
    +++++     +++++

These two kinds of closure nodes can be told apart by the tags in the
pointers pointing to them. This linked list representation makes
"pushing" arguments O(1), and sharing data easy. When forcing a
fully saturated node, the arguments are collected into a buffer (to
provide O(1) and simple access to individual arguments) and passed as
a parameter to the out-of-line function.

# role of haskell's type system

I haven't written a single Haskell program without noticing the
benefits conferred by a well-designed type system. Hoopl, especially,
makes generating incorrect control-flow graphs compile-time
errors. Consider `mapConcatGraph` from `Utils/Graph.hs`, with the type

{% highlight haskell %}
forall n n' m. (UniqueMonad m, NonLocal n, NonLocal n') =>
               (n C O -> m (Graph n' C O),
                n O O -> m (Graph n' O O),
                n O C -> m (Graph n' O C)) ->
               Graph n C C -> m (Graph n' C C)
{% endhighlight %}

which can be used to "expand" nodes or instructions in a Hoopl flow
graph into subgraphs (this is used to implement the HIR to LIR
lowering operation). The type itself states and enforces the property
that a node with a single (or multiple) entry (or exit) can be
replaced only with a graph with a single (respectively multiple) entry
(respectively exit). Without this constraint, keeping the whole
operation well-defined would be difficult. The subgraphs don't need to
be straight lines of code; a subgraph with a single entry and a single
exit could very well look like this:

    { Graph Entry }
    If condition Then Goto LblX
                 Else Goto LblY
    
    LblX: Goto LblZ
    
    LblY: Goto LblZ
    
    LblZ:
    { Graph Exit }


However, the fact that the graph has a single entry and exit means
that it can be "spliced" into the middle of a basic block in the place
of some instruction unambiguously; which would, in this case split the
original basic block into two and create two more basic blocks. More
importantly, I could not have implemented such a function with weaker
constraints and guarantees -- the "well-formedness" of CFGs are
ingrained into the very types used to represent them.

# future work

A minimum working prototype has made a lot of fun sub-projects
possible, some of which I will definitely work on. Two of the most
important ones at this point are a tracing GC and a register
allocator. Other ideas that sound interesting:

  1. Implement CPS conversion and some of the techniques mentioned by
     Olin Sivers in "Taming Lambda" [^5].

  2. Elide type checks using basic data-flow analysis.

  3. LIR doesn't get any optimization passes, despite being in a very
     optimization friendly form. This should be fixed.

[^1]: <http://en.wikipedia.org/wiki/Lambda_calculus>
[^2]: <https://github.com/sanjoy/echoes>
[^3]: <http://en.wikipedia.org/wiki/Evaluation_strategy#Call_by_name>
[^5]: <http://www.ccs.neu.edu/home/shivers/papers/diss.pdf>
