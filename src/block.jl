# TODO parameterise time type?

# TODO Using an abstractvector for values requires some thought. The problem is whether or
#   not it would permit us to have views of an array.
#   Possibly we need a more general type here which can package other representations?
#   See Stheno ColVecs / RowVecs - they have the same problem.
#
#   Also see: https://juliaarrays.github.io/ArraysOfArrays.jl/stable/

function _is_strictly_increasing(x::AbstractVector)
    length(x) < 2 && return true

    previous_value = @inbounds first(x)
    for value in @inbounds(x[2:end])
        if previous_value >= value
            return false
        end
        previous_value = value
    end
    return true
end

"""
Sentinel type for use in the constructor for `Block` below.
"""
struct UncheckedConstruction end
const unchecked = UncheckedConstruction()

"""
    Block{T}()
    Block(times::AbstractVector{DateTime}, values::AbstractVector{T})
    Block(unchecked, times, values)

Represent some data in timeseries.

Conceptually this is a list of `(time, value)` pairs, or "knots". Times must be strictly
increasing — i.e. no repeated timestamps are allowed.

The constructor `Block(times, values)` will verify that the input data satisfies this
constraint, however `Block(unchecked, times, values)` will skip the checks. This is
primarily intended for internal use, where the caller assumes responsibility for the
validity of `times` & `values`.

!!! danger
    `TimeDag` considers instances of `Block` to be completely immutable. Thus, when working
    with functions that accept blocks (e.g. [`TimeDag.run_node!`](@ref)), you must not
    modify `times` or `values` members.
"""
struct Block{T,D<:AbstractDateTime,VTimes<:AbstractVector{D},VValues<:AbstractVector{T}}
    times::VTimes
    values::VValues

    function Block(
        ::UncheckedConstruction, times::VTimes, values::VValues
    ) where {T,D<:AbstractDateTime,VTimes<:AbstractVector{D},VValues<:AbstractVector{T}}
        return new{T,D,VTimes,VValues}(times, values)
    end

    function Block(
        times::VTimes, values::VValues
    ) where {T,D<:AbstractDateTime,VTimes<:AbstractVector{D},VValues<:AbstractVector{T}}
        if length(times) != length(values)
            throw(
                ArgumentError(
                    "Times have length $(length(times)), values $(length(values))"
                ),
            )
        end

        if !_is_strictly_increasing(times)
            throw(ArgumentError("Times are not strictly increasing."))
        end

        # TODO
        #   -> How make times & values immutable? Subclass of AbstractVector that doesn't
        #       implement setindex! ?
        return new{T,D,VTimes,VValues}(times, values)
    end
end

Block{T}() where {T} = Block(unchecked, DateTime[], T[])
Block{T,D}() where {T,D} = Block(unchecked, D[], T[])

function Block(
    knots::Union{AbstractVector{Tuple{D,T}},AbstractVector{Pair{D,T}}}
) where {T,D}
    n = length(knots)
    times = _allocate_times(n)
    values = _allocate_values(T, n)
    for (i, (time, value)) in enumerate(knots)
        @inbounds times[i] = time
        @inbounds values[i] = value
    end
    return Block(times, values)
end

value_type(::Block{T}) where {T} = T

# Blocks are considered immutable from the point of view of `duplicate`.
duplicate_internal(x::Block, ::IdDict) = x

# Equality & hash need to be defined, since we have defined an internal constructor.
Base.hash(a::Block, h::UInt) = hash(a.values, hash(a.times, hash(:Block, h)))
function Base.isequal(a::Block, b::Block)
    a === b && return true
    return isequal(a.times, b.times) && isequal(a.values, b.values)
end
function Base.:(==)(a::Block, b::Block)
    a === b && return true
    return a.times == b.times && a.values == b.values
end

# Implement approximate equality in terms of exact equality for timestamps, but approximate
# for values. Only blocks with the same value type should compare approximately equal.
function Base.isapprox(a::Block{T}, b::Block{T}; kwargs...) where {T}
    isempty(a) && isempty(b) && return true
    a.times == b.times || return false
    return isapprox(a.values, b.values; kwargs...)
end

# Make a block behave like a table with two columns, primarily for printing purposes.
Tables.istable(::Type{<:Block}) = true
Tables.columnaccess(::Type{<:Block}) = true
Tables.columns(block::Block) = block

const _BLOCK_COLUMNNAMES = (:time, :value)
Tables.schema(::Block{T}) where {T} = Tables.Schema(_BLOCK_COLUMNNAMES, (DateTime, T))
Tables.getcolumn(block::Block, i::Int) = Tables.getcolumn(block, _BLOCK_COLUMNNAMES[i])
function Tables.getcolumn(block::Block, nm::Symbol)
    if nm == :time
        return block.times
    elseif nm == :value
        return block.values
    else
        throw(ArgumentError("Unknown column $nm"))
    end
end
Tables.columnnames(::Block) = _BLOCK_COLUMNNAMES

function Base.show(io::IO, block::Block)
    return pretty_table(
        io,
        block;
        title="Block{$(value_type(block))}($(length(block)) knots)",
        tf=tf_markdown,
    )
end

"""Slice the block so we contain values in the interval [time_start, time_end)."""
function _slice(block::Block{T}, time_start::DateTime, time_end::DateTime) where {T}
    i_first = searchsortedfirst(block.times, time_start)
    i_last = searchsortedfirst(block.times, time_end) - 1

    return if (i_first > length(block) || i_last < 1)
        Block{T}()
    elseif (i_first == 1 && i_last == length(block))
        # Avoid constructing views if we want the whole block.
        block
    else
        Block(
            unchecked,
            @inbounds(@view(block.times[i_first:i_last])),
            @inbounds(@view(block.values[i_first:i_last])),
        )
    end
end

"""
Internal implementation of `vcat`.

Expects `blocks` to be non-empty, and all blocks therein to also be non-empty.
"""
_vcat(block::Block) = block
function _vcat(b1::Block{T}, blocks::Block{T}...) where {T}
    # TODO Rather than using vcat here, we could use a function that more intelligently
    # merges views and ranges etc.
    # TODO we could use unchecked here, if we were to check that all the adjacent
    #   elements between blocks were correct.
    return Block(
        vcat(b1.times, (block.times for block in blocks)...),
        vcat(b1.values, (block.values for block in blocks)...),
    )
end

# Fast path for a single block.
Base.vcat(block::Block) = block

function Base.vcat(b1::Block{T}, blocks::Block{T}...) where {T}
    # Do not include empty blocks in concatenation
    blocks = filter(!isempty, blocks)

    return if isempty(b1)
        if isempty(blocks)
            # If `blocks` is also empty, then we should just return a single empty block of
            # the correct type. Blocks are considered immutable, so use `b1`.
            b1
        else
            _vcat(blocks...)
        end
    else
        _vcat(b1, blocks...)
    end
end

# Indexing, iteration, etc.
# NB: constraining length to return an Int here is very important for performance!
Base.length(block::Block)::Int = length(block.times)
Base.isempty(block::Block)::Bool = length(block) == 0
Base.firstindex(block::Block) = 1
Base.lastindex(block::Block) = length(block)
Base.getindex(block::Block, i::Int) = (block.times[i], block.values[i])
Base.getindex(block::Block, i::OrdinalRange{Int}) = Block(block.times[i], block.values[i])

Base.eltype(::Block{T}) where {T} = Tuple{DateTime,T}
function Base.iterate(block::Block, state::Int=1)
    return if (state > length(block))
        nothing
    else
        (block[state], state + 1)
    end
end

_allocate_times(n::Int) = Vector{DateTime}(undef, n)

"""
    _allocate_values(T, n::Int) -> AbstractVector{T}

Allocate some uninitialized memory that looks like a vector{T} of length `n`.
"""
function _allocate_values(T, n::Int)
    # TODO This is not necessarily optimal. See comment near definition of
    #   Block regarding what to do if we're viewing a dense array.
    #   The correct solution will probably involve dispatching based on the type of
    #   input.values.
    return Vector{T}(undef, n)
end

"""Resize the vector to length `n` and attempt to reclaim unused space."""
function _trim!(x::AbstractVector, n::Int)
    # TODO It sounds like this currently doesn't actually free any of the buffer, which
    #   could be a bit inefficient. Maybe sizehint! is required too?
    return resize!(x, n)
end

"""
    _equal_times(a::Block, b::Block) -> Bool

true => the times in blocks `a` and `b` are the same.
false => the times in blocks `a` and `b` may be different, or the same.

This function will try to return true for as many cases as possible, with the guarantee
that it will always run in constant time; i.e. it will never explicitly compare time values.
"""
function _equal_times(a::Block, b::Block)::Bool
    # FIXME This doesn't account for the case where e.g. a.times is a vector, and b.times is
    #   a view of the entirety of a.times.
    return a.times === b.times
end
