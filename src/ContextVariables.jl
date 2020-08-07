module ContextVariables

# Re-exporting `Base` functions so that Documenter knows what's public:
export @contextvar, ContextVar, get, getindex, snapshot_context, with_context

using Logging: AbstractLogger, Logging, current_logger, with_logger
using UUIDs: UUID, uuid4, uuid5

include("payloadlogger.jl")

function _ContextVar end

# `ContextVar` object itself does not hold any data (except the
# default value).  It is actually just a key into the task-local
# context storage.
"""
    ContextVar{T}

Context variable type.  This is the type of the object `var` created by
[`@contextvar var`](@ref @contextvar).  This acts as a reference to the
value stored in a task-local context.  The macro `@contextvar` is the only
public API to construct this object.

!!! warning

    It is unspecified if this type is concrete or not. It may be
    changed to an abstract type and/or include more type parameters in
    the future.
"""
struct ContextVar{T}
    name::Symbol
    _module::Module
    key::UUID
    has_default::Bool
    default::T

    global _ContextVar
    _ContextVar(name, _module, key, ::Type{T}, default) where {T} =
        new{T}(name, _module, key, true, default)
    _ContextVar(name, _module, key, ::Type{T}) where {T} = new{T}(name, _module, key, false)
end

_ContextVar(name, _module, key, ::Nothing, default) =
    _ContextVar(name, _module, key, typeof(default), default)
_ContextVar(name, _module, key, ::Nothing) = _ContextVar(name, _module, key, Any)

#=
baremodule _EmptyModule end

ContextVar{T}(name::Symbol, default) where {T} =
    _ContextVar(name, _EmptyModule, uuid4(), T, default)
ContextVar{T}(name::Symbol) where {T} = _ContextVar(name, _EmptyModule, uuid4(), T)

ContextVar(name::Symbol, default) = ContextVar{typeof(default)}(name, default)
ContextVar(name::Symbol) = ContextVar{Any}(name)

"""
    ContextVar{T}(name::Symbol [, default])
    ContextVar(name::Symbol [, default])

Define *local* context variable.

!!! warning

    Using this constructor to define context variable in the global name space
    (i.e., `const var = ContextVar(:var)`) is not recommended because this is not
    safe to be used with Distribute.jl.  Use `@contextvar var` instead.
"""
ContextVar
=#

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

function Base.show(io::IO, ::MIME"text/plain", var::ContextVar)
    print(io, var._module, '.', var.name, " :: ContextVar")
    if get(io, :compact, false) === false
        print(io, " [", var.key, ']')
        if get(var) === nothing
            print(io, " (not assigned)")
        else
            print(io, " => ")
            show(IOContext(io, :compact => true), MIME"text/plain"(), var[])
        end
    end
end

# The primitives that can be monkey-patched to play with new context
# variable storage types:
"""
    merge_ctxvars(ctx::Union{Nothing,T}, kvs) -> ctx′:: Union{Nothing,T}

!!! warning

    This is not a public API.  This documentation is for making it easier to
    experiment with different implementations of the context variable storage
    backend, by monkey-patching it at run-time.  When this function is
    monkey-patched, `ctxvars_type` should also be monkey-patched to return
    the type `T`.

The first argument `ctx` is either `nothing` or a dict-like object of type `T` where
its `keytype` is `UUID` and `valtype` is `Any`.  The second argument `kvs` is an
iterable of `Pair{UUID,<:Union{Some,Nothing}}` values.  Iterable `kvs` must have
length.

If `ctx` is `nothing` and `kvs` is non-empty, `merge_ctxvars` creates a new
instance of `T`. If `ctx` is not `nothing`, it returns a shallow-copy `ctx′` of
`ctx` where `k => v` is inserted to `ctx′` for each `k => Some(v)` in `kvs`
and `k` is deleted from `ctx′` for each `k => nothing` in `kvs`.
"""
function merge_ctxvars(ctx, kvs)
    # Assumption: eltype(kvs) <: Pair{UUID,<:Union{Some,Nothing}}
    if isempty(kvs)
        return ctx
    else
        # Copy-or-create-on-write:
        vars = ctx === nothing ? ctxvars_type()() : copy(ctx)
        for (k, v) in kvs
            if v === nothing
                delete!(vars, k)
            else
                vars[k] = something(v)
            end
        end
        isempty(vars) && return nothing  # should we?
        return vars
    end
end

ctxvars_type() = Dict{UUID,Any}
_ctxvars_type() = Union{Nothing,ctxvars_type()}
get_task_ctxvars() = _get_task_ctxvars()::_ctxvars_type()

new_merged_ctxvars(kvs) =
    merge_ctxvars(
        get_task_ctxvars(),
        (
            k.key => v === nothing ? v : Some(convert(eltype(k), something(v)))
            for (k, v) in kvs
        ),
    )::_ctxvars_type()

struct _NoValue end

"""
    get(var::ContextVar{T}) -> Union{Some{T},Nothing}

Return `Some(value)` if `value` is assigned to `var`.  Return `nothing` if
unassigned.
"""
function Base.get(var::ContextVar{T}) where {T}
    ctx = get_task_ctxvars()
    if ctx === nothing
        var.has_default && return Some(var.default)
        return nothing
    end
    if var.has_default
        return Some(get(ctx, var.key, var.default)::T)
    else
        y = get(ctx, var.key, _NoValue())
        y isa _NoValue || return Some(ctx[var.key]::T)
    end
    return nothing
end

"""
    getindex(var::ContextVar{T}) -> value::T

Return the `value` assigned to `var`.  Throw a `KeyError` if unassigned.
"""
function Base.getindex(var::ContextVar{T}) where {T}
    maybe = get(var)
    maybe === nothing && throw(KeyError(var))
    return something(maybe)::T
end

"""
    genkey(__module__::Module, varname::Symbol) -> UUID

Generate a stable UUID for a context variable `__module__.\$varname`.
"""
function genkey(__module__::Module, varname::Symbol)
    pkgid = Base.PkgId(__module__)
    if pkgid.uuid === nothing
        throw(ArgumentError(
            "Module `$__module__` is not a part of a package. " *
            "`@contextvar` can only be used inside a package.",
        ))
    end
    fullpath = push!(collect(fullname(__module__)), varname)
    if any(x -> contains(string(x), "."), fullpath)
        throw(ArgumentError(
            "Modules and variable names must not contain a dot:\n" * join(fullpath, "\n"),
        ))
    end
    return uuid5(pkgid.uuid, join(fullpath, '.'))
end

"""
    @contextvar [local|global] var[::T] [= default]

Declare a context variable named `var`.  The type constraint `::T` and
the default value `= default` are optional.  If the default value is given
without the type constraint `::T`, its type `T = typeof(default)` is used.

`@contextvar` without `local` and `global` prefixes can only be used at the
top-level scope of packages with valid UUID.

!!! warning

    Context variables declared with `global` does not work with `Distributed`.

# Examples

Top-level context variables needs to be declared in a package:

```julia
module MyPackage
@contextvar cvar1
@contextvar cvar2 = 1
@contextvar cvar3::Int
end
```
"""
macro contextvar(ex0)
    ex = ex0
    qualifier = :const
    if Meta.isexpr(ex, :local)
        length(ex.args) != 1 && throw(ArgumentError("Malformed input:\n$ex0"))
        ex, = ex.args
        qualifier = :local
    elseif Meta.isexpr(ex, :global)
        length(ex.args) != 1 && throw(ArgumentError("Malformed input:\n$ex0"))
        ex, = ex.args
        qualifier = :global
    end
    if Meta.isexpr(ex, :(=))
        length(ex.args) != 2 && throw(ArgumentError("Unsupported syntax:\n$ex0"))
        ex, default = ex.args
        args = Any[esc(default)]
    else
        args = []
    end
    if Meta.isexpr(ex, :(::))
        length(ex.args) != 2 && throw(ArgumentError("Malformed input:\n$ex0"))
        ex, vartype = ex.args
        pushfirst!(args, esc(vartype))
    else
        pushfirst!(args, nothing)
    end
    if !(ex isa Symbol)
        if ex === ex0
            throw(ArgumentError("Unsupported syntax:\n$ex0"))
        else
            throw(ArgumentError("""
                Not a variable name:
                $ex
                Input:
                $ex0
                """))
        end
    end
    varname = QuoteNode(ex)
    if qualifier === :const
        key = genkey(__module__, ex)
    else
        # Creating a UUID at macro expansion time because:
        # * It would be a memory leak it were created at run-time because
        #   context variable storage can be filled with UUIDs created at
        #   run-time.
        # * Creating it at run-time is doable with function-based interface like
        #   `ContextVar(:name, default)`.
        key = uuid4()
    end
    return Expr(
        qualifier,
        :($(esc(ex)) = _ContextVar($varname, $__module__, $key, $(args...))),
    )
end

"""
    with_context(f, var1 => value1, var2 => value2, ...)
    with_context(f, pairs)

Run `f` in a context with given values set to the context variables.  Variables
specified in this form are rolled back to the original value when `with_context`
returns.  It act like a dynamically scoped `let`.  If `nothing` is passed as
a value, corresponding context variable is cleared; i.e., it is unassigned or
takes the default value.  Use `Some(value)` to set `value` if `value` can be
`nothing`.

    with_context(f, nothing)

Run `f` in a new empty context.  All variables are rewind to the original values
when `with_context` returns.

Note that

```julia
var2[] = value2
with_context(var1 => value1) do
    @show var2[]  # shows value2
    var3[] = value3
end
@show var3[]  # shows value3
```

and

```julia
var2[] = value2
with_context(nothing) do
    var1[] = value1
    @show var2[]  # shows default (or throws)
    var3[] = value3
end
@show var3[]  # does not show value3
```

are not equivalent.
"""
with_context
with_context(f, kvs::Pair{<:ContextVar}...) = with_task_ctxvars(f, new_merged_ctxvars(kvs))
with_context(f, ::Nothing) = with_task_ctxvars(f, nothing)

struct ContextSnapshot{T}
    vars::T
end

# TODO: Do we need to implement `Dict{ContextVar}(::ContextSnapshot)`?
# This requires storing UUID-to-ContextVar mapping somewhere.

"""
    snapshot_context() -> snapshot::ContextSnapshot

Get a snapshot of a context that can be passed to [`with_context`](@ref) to
run a function inside the current context at later time.
"""
snapshot_context() = ContextSnapshot(get_task_ctxvars())

with_context(f, snapshot::ContextSnapshot) = with_task_ctxvars(f, snapshot.vars)

end # module
