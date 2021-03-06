# Concepts

This document explains some key concepts and terminology.

We begin with a mathematical framework for expressing time-series operations.
This is then used to form analogies with code in `TimeDag`, and motivate some of the design decisions.


## Time-series

We define a time-series ``x\ \in \mathcal{TS} \subset \mathcal{T} \times \mathcal{X}`` to be an ordered sequence of ``N`` time-value pairs:
```math
\begin{aligned}
x   &= \{(t_i, x_i)\ |\ i \in [1, N]\}\\
t_i &\in \mathcal{T}_x\ \forall i, \quad \mathcal{T}_x = [t_1, \infty) \subset \mathcal{T}\\
x_i &\in \mathcal{X}\ \forall i\\
t_i &> t_{i-1}\ \forall i.
\end{aligned}
```

Here we use ``\mathcal{T}`` to denote the type of time.[^1]
We only require that there is a total order on ``\mathcal{T}`` — but thinking about it as a real number is a good analogy.
We also, somewhat sloppily, identify ``\infty`` with ``max \mathcal{T}``.

[^1]: We currently require that all times are instances of `DateTime`.
This restriction may be relaxed in the future.

Colloquially, we will refer to a time-value pair as a _knot_.[^2]

[^2]: Diagrams in the alignment section will perhaps be reminiscent of the rope on a [ship log](https://en.wikipedia.org/wiki/Chip_log).

``\mathcal{T}_x`` is the semi-infinite interval bounded below by the time of the first knot in ``x``.

We define the [`TimeDag.value_type`](@ref) of ``x`` to be the set ``\mathcal{X}`` above, and in practice this can be any Julia type.

`TimeDag` primarily represents a time-series as a [`TimeDag.Node`](@ref). 
It also stores time-series data in memory in the [`Block`](@ref) type.

Here is a visualisation of a time-series ``x``:

![A time series](assets/time_series.png)

### Functional interpretation
We can also consider ``x`` to be a function, ``x : \mathcal{T}_x \rightarrow \mathcal{X}``.
This is defined ``x(t) = \max_i\ x_i\ \textrm{s.t.}\ t_i \leq t``.

Informally, this means that whenever we observe a value ``x_i``, the 'value of' the time-series is ``x_i`` until such time as we observe ``x_{i+1}``.

Sometimes it is useful to define ``x(t_{-}) = \oslash\ \forall\ t_{-} \in \mathcal{T} \setminus \mathcal{T}_x``.
Here, ``\oslash`` is a placeholder element that simply means "no value".

!!! info
    Note that time is _strictly increasing_, and repeated times are not permitted.
    This conceptual choice is necessary to consider ``x`` to be a map from time to value as above.
    Without this restriction, there is an ambiguity whenever a time is repeated.


## Functions of time-series

### General case
We wish to define a general notion of a function ``f : \mathcal{TS} \times \cdots \times \mathcal{TS} \rightarrow \mathcal{TS}``.
Let ``z = f(x, y, \ldots)``, where ``x``, ``y`` and ``z`` are all time-series.

Firstly, we define an indicator-like function ``f_t(t, \ldots) \in \{0,1\}``, which returns ``1`` iff we should emit a value at time ``t``:
```math
\{t_i\} = \{t \in \mathcal{T}\ |\ f_t(t, \{x(t') | t' \leq t\}, \{y(t') | t' \leq t\}, \ldots) = 1\}
```

Colloquially, whenever ``f_t`` returns ``1`` we say that ``z`` _ticks_, i.e. emits a knot.

Then, we require that each value ``z_i`` at time ``t_i`` can be written as the result of a function ``f'``:
```math
z_i = f'(t_i, \{x(t) | t \leq t_i\}, \{y(t) | t \leq t_i\}, \ldots).
```

!!! info 
    Let us unpack this notation a bit:
    * Knots of ``z`` are only allowed to depend on _non-future_ values of ``x`` and ``y``.
    * ``z`` can tick whenever it likes, possibly dependent on values of ``x`` and ``y``.
    * The knot emitted can be a function of time.

    The first of these is an important requirement, and `TimeDag` aims to enforce this structurally.

### Parameters
In the above discussion, all arguments to ``f`` are time-series.
Such functions could additionally have some other non-time-series constant parameters, which we will denote ``\theta\in\Theta``.
Strictly mathematically, note that a "constant" can just be viewed as a time-series with a single observation at ``min \mathcal{T}``; so the above description is still fully general.

In practice (for efficient implementation) we will want function ``f : \Theta \times \mathcal{TS} \times \cdots \rightarrow \mathcal{TS}``.
So, ``f(\theta, x, y, \ldots)`` then has some constant parameter(s) ``\theta``.

We'll continue to drop the explicit ``\theta`` dependence where it isn't interesting, to simplify notation.

### Explicit state
It is useful to re-write the value computation by introducing the notion of a 'state' ``\zeta_i``:
```math
\begin{aligned}
z_i, \zeta_i &= f_v(t_i, \zeta_{i-1}, x(t_i), y(t_i), \ldots)\\
\end{aligned}
```
Each state ``\zeta_{i-1}`` needs to package as much information about the history of the inputs as necessary to compute each ``z_i`` (as well as the new state ``\zeta_i``).

### Batching

Note that, even after the re-arrangement in [Explicit state](@ref), ``f_t`` is still a bit awkward.
One cannot directly implement it — otherwise one has to call ``f_t`` for every ``t`` in an infinite (or at least very large) set.

First, let us introduce the notion of slicing.
Define an interval ``\delta = [t_1,t_2) \subset \mathcal{T}``.[^3]
Then, the slice of ``x`` over ``\delta``, which we'll write as ``x' = x[\delta]``, is a new time-series with support ``\mathcal{T}_{x'} = \delta \cap \mathcal{T}_x``.

[^3]: One is free to choose the open/closed-ness of each bound, however the use of an closed-open interval helps in subsequent analysis.

Let ``\{\delta_i\}`` represent an ordered non-overlapping set of intervals, whose union covers all of ``\mathcal{T}``.
We then write, analogous to the definition of ``f_v``:
```math
z[\delta_i], \zeta_{\sup \delta_i} = f_b(\delta_i, \zeta_{\sup \delta_{i-1}}, x[\delta_i], y[\delta_i], \ldots).
```
This function outputs knots — time-value pairs — rather than just the values, and hence performs the roles of both ``f_t`` and ``f_v`` previously.

**NB** ``\sup\delta_i`` indicates the supremum of the interval ``\delta_i``, i.e. the upper bound.
The state ``\zeta`` is only subscripted by this upper bound; i.e. by a time, because it should not be path dependent.
i.e. for a given time-series operation, we should always end up with the same state at a particular time, regardless of how many batches we have used to get there.

!!! info
    It is useful to emphasise this distinction:
    * ``f`` — a time-series operation. This is [`TimeDag.NodeOp`](@ref).
    * ``f_b`` — the _implementation_ of ``f``. This is [`TimeDag.run_node!`](@ref).

    Helpfully, often ``f`` has simple semantics & behaviour that can be reasoned about.
    The implementation details can be ignored in this reasoning.

!!! warning
    A little thought shows that ``f_b``, and hence [`TimeDag.run_node!`](@ref), can express _illegal_ time-series operations that future-peek.
    Care must be taken when implementing this low-level interface!

    Where possible, when custom operations are required, use the higher-level abstractions referred to below.


## Classes of function

All time-series functions in `TimeDag` are of the form of ``f`` above.
Here we identify a few categories of such functions which cover many of the cases of interest.

### No inputs

A function ``f : \emptyset \rightarrow \mathcal{TS}`` can be considered a _source_.
That is, it generates a time-series with no inputs.

In this case, if ``z = f()``, then the implementation ``f_b`` technically reduces to ``z[\delta] = f_b(\delta)``.
In principle no state is required, since there is no external information to remember.
However, in _practice_ retaining the state term can be useful to increase implementation efficiency.

### Single input (map over values)

Consider an unary `-` function operating on a time-series; ``z = -x``.
This is a "boring" time-series operation, in that all times of ``z`` are identical to those of ``x``.
The values are determined by ``z_i = -x_i\ \forall i``.

Some unary operators from `Base`, like `Base.:-`, have methods on [`TimeDag.Node`](@ref) defined within `TimeDag`.

More generally, [`wrap`](@ref) and [`wrapb`](@ref) let you create a time-series function from such an unary function.
See [Creating operations](@ref) for more details.

### Single input (lag)

A [`lag`](@ref) is a slightly more complex unary function.
Rather than explain it mathematically, a visualisation can help:

![lag](assets/lag.png)

Time is increasing to the right.
Each grey arrow indicates that one value is used in computing another — in the case of [`lag`](@ref), the value is simply used directly.
Note how, for this function, we never introduce new timestamps — we simply 'lag' the previous value onto the next timestamp. 

A related concept is a time-lag, where each knot would be delayed by some fixed period of time ``\partial t``:

![Time lag](assets/tlag.png)

### Single input (cumulative sum)

Similarly to a simple function operation on values, a cumulative sum over time ([`Base.sum`](@ref)) ticks whenever the input ticks.
However, this time each value is a function of all preceding knots:

![sum](assets/sum.png)


### Alignment

When considering a function of two or more time-series, a useful special-case is where the output ticks at some subset of the times that all the inputs tick.
We consider _alignment_, which is a selection process with semantics similar (but not identical) to "joins" in database terminology.

We define three ways of performing alignment.
For each one we document the `TimeDag` constant which should be used in function calls that accept an alignment, and give a graphical interpretation.
Each diagram is shown for the case of two inputs; the docstrings describe the general case with more inputs.

Functions in `TimeDag` that accept multiple nodes typically default to using [`UNION`](@ref) alignment.

##### Union
Similar to an "outer join", with the key difference that we only emit knots once _all_ inputs have started ticking.

```@docs
UNION
```
![Union alignment](assets/union_align.png)

##### Intersect
Tick if and only if both inputs tick.
This is identical to an "inner join".

```@docs
INTERSECT
```
![Intersect alignment](assets/intersect_align.png)

##### Left
Similar to a "left join", with the key difference that we only emit knots once _all_ inputs have started ticking.

```@docs
LEFT
```
![Left alignment](assets/left_align.png)

#### Initial values

For the alignments above, it was noted that we have to wait for all inputs to start ticking before the output ticks.

It is possible to tell `TimeDag` that a given operation should consider its inputs to have some _initial values_.
This behaves a little like a knot at the start of the evaluation window, however does *not* result in the creation of an output knot at that time.
In the notation above, it is the definition of a value for ``x(t_{-})`` which isn't ``\oslash``.

Initial values are set seperately for each input.
Most functions of two or more nodes will take an `initial_values` keyword argument to specify these.

Some more implementation details on the lower-level functionality that controls this is provided in [Alignment implementation](@ref).

## Computational graph

### Nodes

So far we have introduced the notion of time-series operations.
By working purely with [`TimeDag.NodeOp`](@ref)s, we build up an abstract representation of the computation we want to do.
A [`TimeDag.Node`](@ref) contains zero or more input nodes, as well as a [`TimeDag.NodeOp`](@ref) defining how they should be combined.

### Evaluation
When we wish to evaluate a node over some interval ``\delta``, we first evaluate all input nodes over the same interval, recursively.
Given all inputs, we can evaluate a particular node using ``f_b``, as defined previously.
The practicalities of this are discussed further in [Advanced evaluation](@ref).

### Subgraph elimination
By using an [Identity map](@ref) we ensure that we never create duplicate nodes.
This effectively eliminates the creation of common subgraphs, which means that when performing evaluation we never repeat work.
