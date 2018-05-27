---
layout: post
title:  "Constructing the Deutsch-Jozsa Algorithm"
needsMathJAX: True
date: 2018-5-27
---

This is a short note on the 1-qbit version of the Deutsch-Jozsa algorithm.  Instead of describing the algorithm and explaining how it works, I've attempted to work backwards from the problem statement.  This helped me understand the concept a little better.

# Problem Statement

Given a quantum implementation of a 1 bit function $$f$$, $$U_f$$, that performs the operation $$U_f \left\vert x y \right\rangle = \left\vert x \right\rangle \left\vert f(x) \oplus y \right\rangle$$, compute $$f(0) \oplus f(1)$$ with just one query to $$U_f$$.  $$\oplus$$ is the binary XOR operation and the weird $$\left\vert f(x) \oplus y \right\rangle$$ bit in $$U_f$$ is a trick to convert a possibly irreversible $$f$$ to a reversible circuit (all quantum circuits are reversible so irreversible functions cannot be implemented as-is as quantum circuits).

# Construction

Let's assume we're looking for a quantum circuit that will give a *deterministic* answer for $$f(0) \oplus f(1)$$.

For this to happen, we'd want one qbit of the output of circuit to be $$\left\vert 0 \right\rangle$$ with probability $$1$$ if $$f(0) \oplus f(1)$$ is $$0$$ and for it to be $$\left\vert 1 \right\rangle$$ with probability $$1$$ if $$f(0) \oplus f(1)$$ is $$1$$.  Without loss of generality, let this measured bit be the 0'th bit.  Since $$U_f$$ deals with two bits, let's also assume this measured bit is one out of two bits[^twobits] in the circuit.

The state of the system before measurement is then $$\left\vert 0 \right\rangle \left( \alpha_{0} \left\vert 0 \right\rangle + \beta_{0} \left\vert 1 \right\rangle \right) + \left\vert 1 \right\rangle \left( \alpha_{1} \left\vert 0 \right\rangle + \beta_{1} \left\vert 1 \right\rangle \right) $$ and we want $$\alpha_0 = \beta_0 = 0$$ when $$a \neq b$$, otherwise we want $$\alpha_1 = \beta_1 = 0$$.

[For brevity let $$f(0)$$ be $$a$$, $$f(1)$$ be $$b$$, and $$\bar{a}$$, $$\bar{b}$$ be their logical NOTs.]

A little bit of fiddling shows that this happens[^ex0] if $$\alpha_{0} \left\vert 0 \right\rangle + \beta_{0} \left\vert 1 \right\rangle$$ is $$\left\vert a \right\rangle - \left\vert \bar{a} \right\rangle + \left\vert b \right\rangle - \left\vert \bar{b} \right\rangle$$ and $$\alpha_{1} \left\vert 0 \right\rangle + \beta_{1} \left\vert 1 \right\rangle$$ is $$\left\vert a \right\rangle - \left\vert \bar{a} \right\rangle - \left\vert b \right\rangle - \left\vert \bar{b} \right\rangle$$.  Therefore we somehow need to have the pre-measurement state be $$ \left\vert 0 \right\rangle \left( \left\vert a \right\rangle - \left\vert \bar{a} \right\rangle + \left\vert b \right\rangle - \left\vert \bar{b} \right\rangle \right)$$ $$+$$ $$\left\vert 1 \right\rangle \left( \left\vert a \right\rangle - \left\vert \bar{a} \right\rangle - \left\vert b \right\rangle + \left\vert \bar{b} \right\rangle \right) $$.

[I've stopped renormalizing the probabilities since that's not super important.]

Re-associating the desired end state, we see it is equal to $$\left( \left\vert 0 \right\rangle + \left\vert 1 \right\rangle \right) \left( \left\vert a \right\rangle - \left\vert \neg a \right\rangle \right)$$ $$+$$ $$\left( \left\vert 0 \right\rangle - \left\vert 1 \right\rangle \right) \left( \left\vert b \right\rangle - \left\vert \neg b \right\rangle \right)$$.  This can be created from $$\left\vert 0 \right\rangle \left( \left\vert a \right\rangle - \left\vert \neg a \right\rangle \right)$$ $$+$$ $$\left\vert 1 \right\rangle \left( \left\vert b \right\rangle - \left\vert \neg b \right\rangle \right)$$ by applying the Hadamard gate to the first qbit.

This pre-Hadamard state expands to $$\left\vert 0 \right\rangle \left\vert a \right\rangle$$ $$-$$ $$\left\vert 0 \right\rangle \left\vert \bar{a} \right\rangle$$ $$+$$ $$\left\vert 1 \right\rangle \left\vert b \right\rangle$$ $$-$$ $$\left\vert 1 \right\rangle \left\vert \bar{b} \right\rangle$$, which is something we know how to compute!  It is simply $$\left\vert 0 \right\rangle \left\vert f(0) \right\rangle$$ $$-$$ $$\left\vert 0 \right\rangle \left\vert f(0) \oplus 1 \right\rangle$$ $$+$$ $$\left\vert 1 \right\rangle \left\vert f(1) \right\rangle$$ $$-$$ $$\left\vert 1 \right\rangle \left\vert f(1) \oplus 1 \right\rangle$$ $$=$$ $$U_f\left( \left\vert 0 \right\rangle \left\vert 0 \right\rangle - \left\vert 0 \right\rangle \left\vert 1 \right\rangle + \left\vert 1 \right\rangle \left\vert 0 \right\rangle - \left\vert 1 \right\rangle \left\vert 1 \right\rangle \right)$$ $$=$$ $$U_f\left( \left( \left\vert 0 \right\rangle + \left\vert 1 \right\rangle \right) \otimes \left(  \left\vert 0 \right\rangle - \left\vert 1 \right\rangle \right) \right)$$ $$=$$ $$U_f\left( H \left\vert 0 \right\rangle \otimes H \left\vert 1 \right\rangle \right)$$ where $$H$$ is the Hadamard gate.  This yields the 1 qbit version of the Deutsch-Jozsa algorithm:

  1. Let $$\left\vert A \right\rangle = H \left\vert 0 \right\rangle$$, $$\left\vert B \right\rangle = H \left\vert 1 \right\rangle$$
  2. Let $$\left\vert C \right\rangle, \left\vert D \right\rangle = U_f\left(\left\vert A \right\rangle, \left\vert B \right\rangle\right)$$
  3. Let $$\left\vert E \right\rangle = H \left\vert C \right\rangle$$
  4. Measure $$\left\vert E \right\rangle$$

[^twobits]: Of course, it is far from obvious that this _has_ to be the case -- it could be that the algorithm we were looking for requires more than two bits.

[^ex0]: For example, if $$a \neq b$$ then $$a = \bar{b}$$ and so $$\left\vert a \right\rangle - {\left\vert \bar{a} \right\rangle} + \left\vert b \right\rangle - \left\vert \bar{b} \right\rangle$$ = $$\left\vert a \right\rangle - {\left\vert \bar{a} \right\rangle} + \left\vert \bar{a} \right\rangle - \left\vert \bar{\bar{a}} \right\rangle$$ = $$0$$.

