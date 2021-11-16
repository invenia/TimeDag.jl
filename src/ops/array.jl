struct GetIndex{T,Args} <: UnaryNodeOp{T}
    args::Args
end

stateless_operator(::GetIndex) = true
time_agnostic(::GetIndex) = true
always_ticks(::GetIndex) = true

operator!(op::GetIndex, x) = getindex(x, op.args...)

"""
    getindex(x::Node, args...)

A node whose values are generated by calling `getindex(value, args...)` on each `value`
obtained from the node `x`.
"""
function Base.getindex(x::Node, args...)
    T = output_type(getindex, value_type(x), map(typeof, args)...)
    return obtain_node((x,), GetIndex{T,typeof(args)}(args))
end

# Special-case optimisations for a single colon.
Base.getindex(x::Node{<:AbstractArray}, ::Colon) = vec(x)
Base.getindex(x::Node{<:Tuple}, ::Colon) = x

"""
    vec(x::Node{<:AbstractArray}) -> Node{<:AbstractVector}

Return a vector whose values are those of `x`, but flattened into a single vector.

If `x` has values which are already an `AbstractVector`, this will be a no-op.
"""
Base.vec(x::Node{<:AbstractArray}) = apply(vec, x)
Base.vec(x::Node{<:AbstractVector}) = x
