module ContextVariables

export ContextVar, with_variables

using Base.Meta: isexpr
using IRTools: @dynamo, IR, recurse!
using UUIDs: UUID, uuid4

const CVKEY = UUID("30c48ab6-eb66-4e00-8274-c879a8246cdb")

struct ContextVar{T}
    name::Symbol
    key::UUID
    has_default::Bool
    default::T

    ContextVar{T}(name::Symbol, default) where {T} = new{T}(name, uuid4(), true, default)
    ContextVar{T}(name::Symbol) where {T} = new{T}(name, uuid4(), false)
end

ContextVar(name::Symbol, default) = ContextVar{typeof(default)}(name, default)
ContextVar(name::Symbol) = ContextVar{Any}(name)

Base.eltype(::Type{ContextVar{T}}) where {T} = T

function Base.show(io::IO, var::ContextVar)
    print(io, ContextVar)
    if eltype(var) !== Any && !(var.has_default && typeof(var.default) === eltype(var))
        print(io, '{', eltype(var), '}')
    end
    print(io, '(', repr(var.name))
    if var.has_default
        print(io, ", ")
        show(io, var.default)
    end
    print(io, ')')
end

Base.getindex(var::ContextVar{T}) where {T} =
    if var.has_default
        get(task_local_storage(CVKEY), var.key, var.default)
    else
        task_local_storage(CVKEY)[var.key]
    end::T

function Base.setindex!(var::ContextVar{T}, value) where {T}
    value = convert(T, value)
    ctx = copy(task_local_storage(CVKEY))
    ctx[var.key] = value
    task_local_storage(CVKEY, ctx)
    return var
end

@dynamo function propagate_variables(args...)
    ir = IR(args...)
    ir === nothing && return
    recurse!(ir)
    return ir
end

# A hack to avoid "this intrinsic must be compiled to be called"
propagate_variables(f::typeof(schedule), args...) = f(args...)

function propagate_variables(::Type{<:Task}, f, args...)
    vars = copy(task_local_storage(CVKEY))
    function wrapper()
        task_local_storage(CVKEY, vars)
        f()
    end
    return Task(wrapper, args...)
end

function with_variables(f, kvs::Pair{Symbol}...)
    with_variables_impl(kvs...) do
        propagate_variables(f)
    end
end

propagate_variables(::typeof(with_variables), args...) = with_variables_impl(args...)

function with_variables_impl(f, kvs::Pair{<:ContextVar}...)
    ctx0 = get(task_local_storage(), CVKEY, nothing)
    if ctx0 === nothing
        ctx = Dict{UUID,Any}()
    else
        ctx = copy(ctx0)
    end
    foldl(push!, (k.key => v for (k, v) in kvs), init = ctx)
    return task_local_storage(f, CVKEY, ctx)
end

end # module
