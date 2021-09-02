module TestContextVariablesX

using Documenter: doctest
using ContextVariablesX
using Test

@contextvar cvar1 = 42
@contextvar cvar2::Int
@contextvar cvar3
@contextvar cvar4::Union{Missing,Int64} = 1

@testset "typed, w/ default" begin
    ok = Ref(0)
    @sync @async begin
        with_context() do
            @test cvar1[] == 42
            with_context(cvar1 => 0) do
                @test cvar1[] == 0
                ok[] += 1
                @async begin
                    @test cvar1[] == 0
                    ok[] += 1
                end
                with_context(cvar1 => 1) do
                    @test cvar1[] == 1
                    ok[] += 1
                end
                @test cvar1[] == 0
                ok[] += 1
            end
        end
    end
    @test ok[] == 4
end

@testset "typed, w/o default" begin
    with_context() do
        @test_throws InexactError with_context(cvar2 => 0.5) do
        end
        @test_throws KeyError cvar2[]
        with_context(cvar2 => 1.0) do
            @test cvar2[] === 1
        end
    end
end

@testset "untyped, w/o default" begin
    with_context(cvar3 => 1) do
        @test cvar3[] === 1
        with_context(cvar3 => 'a') do
            @test cvar3[] === 'a'
        end
    end
end

@testset "show" begin
    @test endswith(sprint(show, cvar1), "ContextVar(:cvar1, 42)")
    @test endswith(sprint(show, cvar2), "ContextVar{$Int}(:cvar2)")
    @test endswith(sprint(show, cvar3), "ContextVar(:cvar3)")
    @test endswith(sprint(show, cvar4), "ContextVar{Union{Missing, Int64}}(:cvar4, 1)")
end

@testset "invalid name" begin
    name = Symbol("name.with.dots")
    err = try
        @eval @contextvar $name
        nothing
    catch err_
        err_
    end
    @test err isa Exception
    @test occursin("Modules and variable names must not contain a dot", sprint(showerror, err))
end

@testset "logging: keyword argument" begin
    logs, _ = Test.collect_test_logs() do
        @sync @async begin
            with_context() do
                try
                    error(1)
                catch err
                    @error "hello" exception = (err, catch_backtrace())
                end
            end
        end
    end
    l, = logs
    @test l.message == "hello"
    @test haskey(l.kwargs, :exception)
    exception = l.kwargs[:exception]
    @test exception isa Tuple{Exception,typeof(catch_backtrace())}
    @test exception[1] == ErrorException("1")
end

@testset "with_logger" begin
    logger = Test.TestLogger()
    with_context(cvar1 => 111) do
        ContextVariablesX.with_logger(logger) do
            @test cvar1[] == 111
            @info "hello"
        end
    end
    l, = logger.logs
    @test l.message == "hello"
end

@testset "doctest" begin
    doctest(ContextVariablesX)
end

end  # module
