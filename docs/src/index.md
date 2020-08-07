# ContextVariables.jl

ContextVariables.jl is heavily inspired by
[`contextvars`](https://docs.python.org/3/library/contextvars.html) in
Python (see also
[PEP 567](https://www.python.org/dev/peps/pep-0567/)).

## Tutorial

### Basic usage

Context variables can be used to manage task-local states that are
inherited to child tasks.  Context variables are created by
[`@contextvar`](@ref):

```julia
@contextvar cvar1           # untyped, without default
@contextvar cvar2 = 1       # typed (Int), with default
@contextvar cvar3::Int      # typed, without default
```

Note that running above code in REPL will throw an error because this
form work only within a package namespace.  To play with `@contextvar`
in REPL, you can prefix the variable name with `global`:

```@meta
DocTestSetup = quote
    using ContextVariables
    function display(x)
        show(stdout, "text/plain", x)
        println()
    end
end
```

```jldoctest tutorial
julia> @contextvar global x::Any = 1;
```

!!! warning

    `@contextvar global` should be used only for interactive exploration,
    quick scripting, and testing.  Using `@contextvar global` inside
    packages make it impossible to work with serialization-based libraries
    such as Distributed.

You can be get a context variable with indexing syntax `[]`

```jldoctest tutorial
julia> x[]
1
```

It's not possible to set a context variable.  But it's possible to run
code inside a new context with new values bound to the context
variables:

```jldoctest tutorial
julia> with_context(x => 100) do
           x[]
       end
100
```

### Dynamic scoping

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

julia> with_context(demo1, x => :a, z => 0);
x[] = :a
y[] = 1
z[] = 0
```

Note that `with_context(f, x => nothing, ...)` clears the value of
`x`, rather than setting the value of `x` to `nothing`.  Use
`Some(nothing)` to set `nothing`.  Similar caution applies to
`set_context` (see below).

```jldoctest tutorial
julia> with_context(x => Some(nothing), y => nothing, z => nothing) do
           @show x[]
           @show y[]
           @show get(z)
       end;
x[] = nothing
y[] = 1
get(z) = nothing
```

Thus,

```julia
with_context(x => Some(a), y => Some(b), z => nothing) do
    ...
end
```

can be used considered as a dynamically scoped version of

```julia
let x′ = a, y′ = b, z′
    ...
end
```

Use `with_context(f, nothing)` to create an empty context and rollback the entire
context to the state just before calling it.

```jldoctest tutorial
julia> with_context(y => 100) do
           @show y[]
           with_context(nothing) do
               @show y[]
           end
       end;
y[] = 100
y[] = 1
```

### Snapshot

A handle to the snapshot of the current context can be obtained with
[`snapshot_context`](@ref).  It can be later restored by [`with_context`](@ref).

```jldoctest tutorial
julia> x[]
1

julia> snapshot = snapshot_context();

julia> with_context(x => 100) do
           with_context(snapshot) do
               @show x[]
           end
       end;
x[] = 1
```

### Concurrent access

The context is inherited to the child task when the task is created.
Thus, changes made after `@async`/`@spawn` or changes made in other tasks are
not observable:

```julia
julia> function demo2()
           x0 = x[]
           with_context(x => x0 + 1) do
               (x0, x[])
           end
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

### Namespace

Consider packages and modules with the same variable name:

```julia
module PackageA
    @contextvar x = 1
    module SubModule
        @contextvar x = 2
    end
end
```

and

```julia
module PackageB
    @contextvar x = 3
end
```

When these packages are loaded, there are three _distinct_ context variables
`PackageA.x`, `PackageA.SubModule.x`, and `PackageB.x` that can be manipulated
independently.

This is simply because `@contextvar` creates independent variable "instance"
in each context.  It can be demonstrated easily in the REPL:

```jldoctest tutorial; filter = r"(^(.*?\.)?x)|(\[.*?\])"m
julia> @contextvar global x;

julia> a = x
Main.x :: ContextVar [4630fcbd-7f5b-4094-916a-f3b33acf4453] (not assigned)

julia> @contextvar global x;

julia> b = x
Main.x :: ContextVar [f6a7639c-3b33-414e-98bc-504b40a48cb8] (not assigned)

julia> a != b
true

julia> with_context(a => 1, b => 2) do
           display(a)
           display(b)
       end
Main.x :: ContextVar [4630fcbd-7f5b-4094-916a-f3b33acf4453] => 1
Main.x :: ContextVar [f6a7639c-3b33-414e-98bc-504b40a48cb8] => 2
```

```@meta
DocTestSetup = nothing
```

## Reference

```@autodocs
Modules = [ContextVariables]
Private = false
```
