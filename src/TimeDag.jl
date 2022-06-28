module TimeDag

using AbstractTrees
using AssociativeWindowAggregation
using Bijections
using DataStructures
using Dates
import Dates: AbstractDateTime
using LightGraphs
using LinearAlgebra
using PrettyTables
using Random
using RecipesBase
using StaticArrays
using Statistics
using Tables
using TeaFiles
using TimeZones

# Types.
export Block
# Singletons.
export INTERSECT, LEFT, UNION
# Node creation.
export wrap, wrapb
# Source nodes.
export block_node, constant, empty_node, iterdates, pulse, tea_file
# Alignment nodes.
export active_count, align, coalign, first_knot, lag, right, left, throttle
# Other nodes
export history, ema
# Evaluation & other utilities.
export evaluate, value_type

include("maybe.jl")

include("core.jl")
include("identity_map.jl")
include("constant.jl")  # Constant nodes are special, so we need to know about them first.

include("output_type.jl")

include("block.jl")
include("graph.jl")
include("evaluation.jl")
include("plotting.jl")

include("alignment.jl")

include("ops/common.jl")  # This defines macros useful for definition of other nodes.
include("ops/window.jl")  # Common stuff for windowed ops.

include("ops/align.jl")
include("ops/array.jl")
include("ops/conditional.jl")
include("ops/history.jl")
include("ops/lagging.jl")
include("ops/random.jl")
include("ops/simple.jl")
include("ops/sources.jl")
include("ops/stats.jl")

end
