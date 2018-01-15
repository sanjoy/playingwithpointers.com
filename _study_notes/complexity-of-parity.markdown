---
layout: post
title:  "Parity, Circuits, and the Polynomial-Time Hierarchy"
needsMathJAX: True
date: 2018-1-14
---

Furst, Merrick, James B. Saxe, and Michael Sipser. "Parity, circuits, and the polynomial-time hierarchy." Theory of Computing Systems 17.1 (1984): 13-27.

# Synopsis

Parity cannot be decided by a circuit in $$AC^0$$ (see <https://en.wikipedia.org/wiki/AC0>).

I skipped section 2, which has some more results about the polynomial-time hierarchy.

The proof proceeds by contradiction: a polynomial sized depth $$d$$ parity circuit can be used to construct a polynomial sized depth $$d - 1$$ parity circuit, which means there can't be a "smallest" $$d$$.

# Tricks I Learned

You can prove the existence of something by demonstrating that the probability of its existence is non-zero (sounds trivial when you say it :) ).  This can be easier than, say, counting arguments, in some cases.
 
You can sometimes do "artificial" case analysis on a function by splitting its domain into convenient subsets.
