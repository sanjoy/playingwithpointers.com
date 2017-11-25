---
layout: post
title:  "Classical Mechanics Study Notes"
permalink: the-theoretical-minimum-classical-mechanics.html
keywords: "physics"
needsMathJAX: True
---

These are some study notes I made for the
excellent
[Classical Mechanics](http://theoreticalminimum.com/courses/classical-mechanics/2011/fall) course
from [The Theoretical Minimum](http://theoreticalminimum.com/) program.  They're
mostly for my personal use, but I'm putting them here in case someone else find
these useful.

# Admissible Laws

A physical law constitutes of a phase space $$\phi$$ and a transition function
$$f$$.  In a discrete setting, the physical system evolves as $$P_{t+1} =
f(P_t)$$ with $$P_t, P_{t+1} \in \phi$$.  The transition function needs to be:

  1. Deterministic -- knowing the state at time $$t$$ is enough to compute the
     state at an arbitrary time in future.  This just follows from $$f$$ being a
     function.
  2. Reversible -- knowing the state at time $$t$$ is enough to compute the
     state at an arbitrary time in the past ("information preserving", in other
     words).  See Liouville's theorem below for a more formal statement.

## Example of an inadmissible law

Aristotle's law of motion $$m\dot{\overrightarrow{x}} = \overrightarrow{F}$$ is
inadmissible.  To see why, consider what happens if we attach a block of mass
$$1$$ to a spring with spring constant $$1$$.  Then the law of motion becomes
$$\dot{x} = -x$$, which solves to $$x=x_0 e^{-t}$$.  This transition function is
not reversible -- the final state for every initial state is $$x = 0$$.

# Lagrangian Mechanics

Every physical system has an associated Lagrangian = $$L(q, \dot{q}, t)$$ where
$$q$$ is the state of the system (coordinates in phase space) and $$t$$ is time.
For many (but not all!)  simple systems $$L(q, \dot{q}, t) = K(\dot{q}) - V(q)$$
where $$K$$ is the kinetic energy of the system and $$V$$ is the potential
energy of the system.  $$L$$ does not always cleanly separate into kinetic and
potential energies this way.

$$P_i$$, the generalized (or canonical) momentum with respect to the $$i^{th}$$
coordinate, is defined to be $$\frac{dL}{d\dot{q_i}}$$.

The Euler-Lagrange equation dictates the laws of motion: 

$$\begin{equation}
\frac{dP_i}{dt} = \frac{\partial L}{\partial q_i}\tag{EL.1}
\end{equation}$$

These are derived by applying
the
[the principle of least action](https://en.wikipedia.org/wiki/Principle_of_least_action),
though I could not grasp why the principle of least action is alluded to be more
fundamental than $$EL.1$$.

# Symmetries and Conservation

A "symmetry" is a change in the inputs to the Lagrangian through which the value
of the Lagrangian does not change.

## Co-ordinate translation symmetry

If $$L$$ is invariant under the change $$\partial q_i = f_i(\overrightarrow{q})
\epsilon$$ then the quantity $$Q = \sum_{i} P_{i} f_i(\overrightarrow{q})$$ is
conserved.

## Time translation symmetry

The Hamiltonian of a system, $$H$$, is defined as:

$$\begin{equation}
H = \sum_i P_i \dot{q}_i - L(q, \dot{q}) \tag{H.Definition}
\end{equation}$$

Then using the Euler-Lagrange equations, we can show that $$\frac{dH}{dt} =
\frac{\partial L}{\partial t}$$.  If $$L$$ does not depend directly on $$t$$
then we say $$L$$ has time-translation symmetry, and it follows that $$H$$ does
not change with time.  $$H$$ is the definition of energy, so time-translation
symmetry implies energy conservation.

# Hamiltonian Mechanics

$$H$$ can be written as a function of $$p$$ and $$q$$ by solving for $$\dot q$$ in terms
of $$p$$.  In cases where we can't solve for $$\dot q$$ the Hamiltonian is invalid
(disallowed by quantum mechanics in ways not covered in this course).

Hamilton's equations (as opposed to Euler-Lagrange) are symmetric in how they
treat momentum and position:

$$\begin{equation}
\frac{\partial H}{\partial p_i}=\dot{q_i}\tag{H.1}
\end{equation}$$

$$\begin{equation}
\frac{\partial H}{\partial q_i}=-\dot{p_i}\tag{H.2}
\end{equation}$$

# Liouville's Theorem

In Hamiltonian mechanics the phase space is a set of points with coordinates
$$p_i$$ and $$q_i$$, and each point moves around with time.  Liouville's theorem
(formal and continuous analog of "physical laws need to be reversible") states
that there are no sinks and sources in this "fluid".

Proof sketch: let $$V_{p_i}$$ be $$\dot p_i$$ and $$V_{q_i}$$ be $$\dot q_i$$.
Then $$V_{p_i}$$ and $$V_{q_i}$$ form a vector field $$\overrightarrow V$$, such
that $$\overrightarrow{\nabla} \cdot \overrightarrow{V} = 0$$ (using algebra +
Hamilton's equations)[^nabla].

[^nabla]: The divergence of a vector field $$V$$ is defined as
    $$\overrightarrow{\nabla} \cdot \overrightarrow{V} = \sum_i \frac{\partial
    V_i}{\partial x_i}$$.

# Poisson Brackets

Poisson brackets are a notation defined as:

$$\begin{equation}
\{F,G\} = \sum_i \frac{\partial F}{\partial q_i} \frac{\partial H}{\partial p_i} - \frac{\partial F}{\partial p_i} \frac{\partial H}{\partial q_i} \tag{Poisson}
\end{equation}$$
  
With this notation, Hamilton's equation can stated as: for any function $$F$$
over the phase space of a system, $$\dot F = \{F,H\}$$.

Given a quantity $$Q$$ which is conserved, $$\{F, Q\}$$ gives us the small
change in $$F$$ under the symmetry operation that conserves $$Q$$.  So, e.g.,
$$\{F, I\}$$ (where $$I$$ is the angular momentum) gives us the change in $$F$$ due to
a small rotation.  $$\dot F = \{F,H\}$$ is just an application of this principle
since $$H$$ is conserved on time translation.

# Magnetic and Electrostatic Forces

## Gradient, divergence and curl

$$\begin{equation}
\overrightarrow{\nabla} S = \frac{dS}{dx_i} \hat{i} + \frac{dS}{dx_j} \hat{j} + \frac{dS}{dx_k} \hat{k} \tag{Gradient}
\end{equation}$$

$$\begin{equation}
\overrightarrow{\nabla} \cdot \overrightarrow{V} = \frac{dV_i}{dx_i} \hat{i} + \frac{dV_j}{dx_j} \hat{j} + \frac{dV_k}{dx_k} \hat{k}\tag{Divergence}
\end{equation}$$

Let $$\epsilon$$ be the [Levi-Civita symbol](https://en.wikipedia.org/wiki/Levi-Civita_symbol).  Then:

$$\begin{equation}
\overrightarrow{V} \times \overrightarrow{A} = \sum_i \epsilon_{i j k} V_j A_k \hat{i}\tag{Cross product}
\end{equation}$$

$$\begin{equation}
\overrightarrow{\nabla} \times \overrightarrow{A} = \sum_i \epsilon_{i j k} \frac{dA_k}{dx_i} \hat{i}\tag{Curl}
\end{equation}$$

Two pertinent algebraic facts:

  1. The divergence of a vector field is $$0$$ iff that field is a curl of some
     field.
  2. The curl of a field is $$0$$ iff the field is a gradient of some (scalar)
     field.
  
## Vector potential
  
Experimentally, we know that magnets do not have mono-poles, which is another
way of saying that the divergence of a magnetic field, $$B$$, is always $$0$$.
Therefore $$B$$ must be the curl of another field; call it $$A$$ (vector
potential).  $$A$$ is not unique -- adding a gradient (of some scalar) to it
keeps $$B$$ the same while changing $$A$$.  This operation of changing $$A$$ by
adding a gradient is called a "gauge transformation".

$$B$$ is measurable while $$A$$ is not, but $$A$$ is necessary to write out the
Lagrangian.

## Electromagnetic force

Let $$V(x)$$ be the electric potential.  Then

$$\begin{equation}
E(x) = - \overrightarrow{\nabla} V(x) \tag{Electric field}
\end{equation}$$

and

$$F = e\left(\overrightarrow{E(x)} + \frac{\overrightarrow{v}}{c} \times \overrightarrow{B}\right) \tag{Electromagnetic force}$$

The second term in $$F$$ is the Lorentz force.  This is similar to
the [Coriolis force](https://en.wikipedia.org/wiki/Coriolis_force).

## Lagrangian and Hamiltonian

The electric potential energy is simple, so let's focus on the part of the
Lagrangian due to the magnetic field (i.e. assume electric field is $$0$$):

$$\begin{equation}
L = \frac{1}{2}mv^2 + \frac{e}{c} \overrightarrow{A} \cdot \dot{\overrightarrow{x}}
\end{equation}$$

We can use the principle of least action to show that gauge transformations do
not affect observable behavior of a system.

From $$L$$ we get $$P_i = m \dot{x} + \frac{e}{c}A_i$$.  This means the
Hamiltonian is 

$$\begin{equation}
H = \sum_i \frac{1}{2m}(P_i - \frac{e}{c}A_x)^2
\end{equation}$$

Note that $$H$$ is basically just $$\frac{1}{2}mv^2$$.
