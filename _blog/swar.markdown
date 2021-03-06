---
layout: post
title:  "A SWAR Algorithm for Popcount"
redirect_from:
 - /swar.html
keywords: "SWAR, bit math, C, C++, low level"
date: 2013-03-02
---

An interesting way to get the _popcount_, or the number of bits set in
an integer is via a SWAR (SIMD Within A Register) algorithm.  While
its performance is very good (16 instructions when compiled with `gcc
-O3`), why the algorithm works is somewhat opaque:

{% highlight c %}
int swar(uint32_t i) {
  i = i - ((i >> 1) & 0x55555555);
  i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
  return (((i + (i >> 4)) & 0x0F0F0F0F) * 0x01010101) >> 24;
}
{% endhighlight %}

For the time being, we assert that the above function is the same as
the more verbose one below. Note how we distribute integer addition
over bitwise `&` in (C) -- this isn't true in general and will be
justified later.

{% highlight c %}
int swar_expanded(uint32_t i) {
  uint32_t j = (i >> 1) & 0x55555555;
  i = i - j; // (A)
  i = (i & 0x33333333) + ((i >> 2) & 0x33333333); // (B)
  i = (i & 0x0F0F0F0F) + ((i >> 4) & 0x0F0F0F0F); // (C)
  i = i * 0x01010101; // (D)
  return i >> 24;
}
{% endhighlight %}


(For the rest of this post, β(n) is the number of ones in the binary
representation of n (so `swar(n)` calculates β(n) for a 32 bit `n`);
and ⟨ a b c ... ⟩ denotes the binary number that has a as its more
significant bit, b as its second most significant bit and so on.)

Notice how a 32 bit integer can been seen as a sequence of 32 1 bit
integers, each with the property that the integer contains the number
of high bits in itself?  Statement (A) of the algorithm expands this
condition to hold for two bits. If `i` is ⟨ b0 b1 b2 ... ⟩, then this
is how `j` lines up with it:

    i = ⟨ b0 b1 b2 b3 b4 b5 b6 b7 b8 ... ⟩
    j = ⟨  0 b0  0 b2  0 b4  0 b6  0 ... ⟩

Since ⟨ b0 b1 ⟩ ≥ ⟨ b0 ⟩, carry from one 2-bit tuple can't "spill
over" to a higher 2-bit tuple. This means bits 2k and (2k + 1) of `(i
- j)` is determined by corresponding bits of `i` and the transform can
be completely described by this table:

    T(⟨ 0 0 ⟩) = ⟨ 0 0 ⟩
    T(⟨ 0 1 ⟩) = ⟨ 0 1 ⟩
    T(⟨ 1 0 ⟩) = ⟨ 0 1 ⟩
    T(⟨ 1 1 ⟩) = ⟨ 1 0 ⟩

Do you see the pattern above? `T(⟨a b⟩)` is β(⟨a b⟩)! If `i` was ⟨ b0
b1 b2 ... ⟩, `(i - j)` is ⟨ c0 c1 c2 ... ⟩ such that ⟨ c(2k) c(2k + 1)
⟩ is β(⟨ b(2k) b(2k + 1) ⟩).

Statement (B) expands this condition further to hold for 4 bit
sequences, as can be seen from how `(i & 0x33333333)` and `((i >> 2) &
0x33333333)` line up:

        0  0 c2 c3  0  0 c6 c7  0  0 ...
     +       c0 c1  0  0 c4 c5  0  0 c8 c9 ...
     = d0 d1 d2 d3 ...

In the above example, the first four bits had ⟨ c0 c1 ⟩ + ⟨ c2 c3 ⟩
ones (because of (A)); which is exactly equal to ⟨ d0 d1 d2 d3
⟩. Statement (C) expands this condition to hold for groups of 8 bits
in exactly the same way.

In (D), multiplying by `0x01010101` sets the most significant byte of
the result to the sum of the all the bytes (assuming there are no
inter-byte carries). This is exactly what we were trying to compute —
the total number of high bits in the input! We right shift by 24 to
get to the MSB and return it.

The optimized version combines (C) to `((i + (i >> 4)) & 0x0F0F0F0F)`
= (E), so that we do one bitwise `&` instead of two. While `(a + b) &
c` is not always the same as `(a & c + b & c)`, they are equal in this
case. To "prove" this informally, we see that for `i` = ⟨ x0 x1 x2
... ⟩ (C) is

        0  0  0  0 x4 x5 x6 x7 ...
     +  0  0  0  0 x0 x1 x2 x3 ...

and (E) is

       x0 x1 x2 x3 x4 x5 x6 x7 x8 x9 ...
     +  0  0  0  0 x0 x1 x2 x3 x4 x5 ...
     &  0  0  0  0  1  1  1  1  0  0 ...

and that for (C) and (E) to be different, an overflowed bit should
have changed bit 7. But there won't be an overflow past, say, bit 12
since ⟨ x12 x13 x14 x15 ⟩ + ⟨ x8 x9 x10 x11 ⟩ ≤ 8 and hence can fit in
four bits.

As a concept check, I suggest implementing a 64 bit version. Here is
my solution:

{% highlight c %}
int pop_cnt_64(uint64_t i) {
  i = i - ((i >> 1) & 0x5555555555555555);
  i = (i & 0x3333333333333333) + ((i >> 2) & 0x3333333333333333);
  return (((i + (i >> 4)) & 0x0F0F0F0F0F0F0F0F) *
          0x0101010101010101) >> 56;
}
{% endhighlight %}

This is probably slightly slower than the 32 bit version since the
integer literals now need to be moved into registers explicitly before
they can be used (they're too large to be embedded as
immediates). Note that the patterns for the integer literals remained
the same. How will they change for a (hypothetical) `pop_cnt_512`?
