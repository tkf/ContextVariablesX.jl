# ContextVariables.jl

ContextVariables.jl is heavily inspired by
[`contextvars`](https://docs.python.org/3/library/contextvars.html) in
Python (see also
[PEP 567](https://www.python.org/dev/peps/pep-0567/)).

## Tutorial

Context variables can be used to manage task-local states that are
inherited to child tasks.  Context variables can be created by
[`@contextvar`](@ref):

```julia
@contextvar cvar1           # untyped, without default
@contextvar cvar2 = 1       # typed (Int), with default
@contextvar cvar3::Int      # typed, without default
```

Note that running above code in REPL will throw an error because this
form work only within a package namespace.  To play with `@contextvar`
in REPL, you can prefix the variable name with `global`:

```jldoctest tutorial; setup = :(using ContextVariables)
julia> @contextvar global x;
```

!!! warning

    `@contextvar global` should be used only for interactive exploration,
    quick scripting, and testing.  Using `@contextvar global` inside
    packages make it impossible to work with serialization-based libraries
    such as Distributed.

The value of context variable can be get and set with the indexing syntax `[]`

```jldoctest tutorial
julia> x[] = 1;

julia> x[]
1
```

The value can be unset with `delete!`:

```jldoctest tutorial
julia> delete!(x);

julia> x[]
ERROR: KeyError: key ContextVar(:x) not found
```

Use [`get`](@ref) and [`set!`](@ref) to handle context variables that may not be
assigned:

```jldoctest tutorial
julia> get(x)  # returns `nothing`

julia> set!(x, Some(1));  # equivalent to `x[] = 1`

julia> get(x)
Some(1)

julia> set!(x, nothing);  # equivalent to `delete!(x)`
```

This is useful to rollback a context variable without knowing the current value
of it:

```julia
old = get(x)
x[] = some_value
do_something()
set!(x, old)  # rollback `x` to the previous state (may not be assigned)
```

[`with_context`](@ref) can be used to set multiple context variables at once,
run a function in this context, and then rollback them to the original state:

```jldoctest tutorial
julia> @contextvar global y = 1;
       @contextvar global z::Int;

julia> function demo1()
           @show x[]
           @show y[]
           @show z[]
       end;

julia> z[] = 100;

julia> with_context(demo1, x => :a, z => 0);
x[] = :a
y[] = 1
z[] = 0

julia> z[]
100
```

Note that `with_context(f, x => nothing, ...)` clears the value of
`x`, rather than setting the value of `x` to `nothing`.  Use
`Some(nothing)` set `nothing`.  Similar caution applies to
`set_context` (see below).

```jldoctest tutorial
julia> with_context(x => Some(nothing), y => nothing, z => nothing) do
           @show x[]
           @show y[]
           @show get(z)
       end
x[] = nothing
y[] = 1
get(z) = nothing
```

Thus,

```julia
with_context(x => Some(a), y => Some(b), z => Some(c)) do
    ...
end
```

can be used considered as a dynamically scoped version of

```julia
let x′ = a, y′ = b, z′ = c
    ...
end
```

Note that `with_context(f, var => value, ...)` does not rollback the context
variables that are not specified by the input:

```jldoctest tutorial
julia> with_context(x => :a) do
           z[] = 0
       end;

julia> z[]
0
```

Use `with_context(f, nothing)` to create an empty context and rollback the entire
context to the state just before calling it.

```jldoctest tutorial
julia> with_context(nothing) do
           z[] = 123
       end;

julia> z[]
0
```

Since setting multiple context variables at once is more efficient than setting
them sequentially, [`set_context`](@ref) can be used to set multiple context
variables in the current context in one go:

```jldoctest tutorial
julia> set_context(x => 1, y => 2, z => 3);

julia> (x[], y[], z[])
(1, 2, 3)
```

A handle to the snapshot of the current context can be obtained with
[`snapshot_context`](@ref).  It can be later restored by [`reset_context`](@ref).

```jldoctest tutorial
julia> x[]
1

julia> snapshot = snapshot_context();

julia> x[] = 123;

julia> reset_context(snapshot);

julia> x[]
1
```

Note that the context is inherited to the child task when the task is created.
Thus, changes made after `@async`/`@spawn` or changes made in other tasks are
not observable:

```julia
julia> function demo2()
           x0 = x[]
           x[] += 1
           (x0, x[])
       end

julia> with_context(x => 1) do
           @sync begin
               t1 = @async demo2()
               t2 = @async demo2()
               result = demo2()
               [result, fetch(t1), fetch(t2)]
           end
       end
3-element Array{Tuple{Int64,Int64},1}:
 (1, 2)
 (1, 2)
 (1, 2)
```

In particular, manipulating context variables using the public API is always
data-race-free.

!!! warning

    If a context variable holds a mutable value, it is a data-race to mutate the
    _value_ when other threads are reading it.

    ```julia
    @contextvar local x = [1]  # mutable value
    @sync begin
        @spawn begin
            value = x[]        # not a data-race
            push!(value, 2)    # data-race
        end
        @spawn begin
            value = x[]        # not a data-race
            @show last(value)  # data-race
        end
    end
    ```

## Reference

```@autodocs
Modules = [ContextVariables]
Private = false
```
