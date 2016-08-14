---
layout: post
title:  "A Proof Bug"
permalink: subtle-proof-bug.html
keywords: "proof, bug, turing machine"
needsMathJAX: True
---

Can you spot why the following proof sketch is incorrect?

# Provability is Undecidable in Peano Arithmetic

Since Peano arithmetic has a finite set of axioms, it is possible to
write a Turing machine that will enumerate all possible proofs in
Peano.  Given a theorem $$T$$, it is possible to construct a Turing
Machine $$TM$$ such that $$TM$$ halts once it has a proof for $$T$$.
It follows that if we have a procedure that can decide if $$T$$ is
provable, we can use the same procedure to decide if $$TM$$ halts;
meaning solving provability implies solving the halting problem.
Hence there can be no procedure deciding provability for Peano.

# The Bug

The above proof misstates the halting problem -- the halting problem
doesn't say halting is not decidable for arbitrary Turing machines,
but that there is no way to decide halting _in general_.  It is
entirely possible that halting is decidable for the class or subset of
Turing machines all instances of $$TM$$ (as defined above) belong to.
In fact, using the above pattern, you could show how checking if a
string belongs to a regular language is undecidable (which of course
isn't true).
