module TestContextVariables

using ContextVariables
using ContextVariables: with_variables_impl
using Test

const cvar1 = ContextVar(:cvar1, 42)
const cvar2 = ContextVar{Int}(:cvar2)
const cvar3 = ContextVar(:cvar3)

@testset "typed, w/ default" begin
    ok = Ref(0)
    @sync @async begin
        with_variables() do
            @test cvar1[] == 42
            cvar1[] = 0
            @test cvar1[] == 0
            ok[] += 1
            @async begin
                @test cvar1[] == 0
                ok[] += 1
            end
            with_variables(cvar1 => 1) do
                @test cvar1[] == 1
                ok[] += 1
            end
            @test cvar1[] == 0
            ok[] += 1
        end
    end
    @test ok[] == 4
end

@testset "typed, w/o default" begin
    with_variables_impl() do
        @test_throws InexactError cvar2[] = 0.5
        @test_throws KeyError cvar2[]
        cvar2[] = 1.0
        @test cvar2[] === 1
    end
end

@testset "untyped, w/o default" begin
    with_variables_impl() do
        cvar3[] = 1
        @test cvar3[] === 1
        cvar3[] = 'a'
        @test cvar3[] === 'a'
    end
end

@testset "show" begin
    @test endswith(sprint(show, ContextVar(:x, 42)), "ContextVar(:x, 42)")
    @test endswith(sprint(show, ContextVar{Int}(:x)), "ContextVar{$Int}(:x)")
    @test endswith(sprint(show, ContextVar(:x)), "ContextVar(:x)")
    @test endswith(sprint(show, ContextVar{Union{Missing,Int64}}(:x, 1)),
                   "ContextVar{Union{Missing, Int64}}(:x, 1)")
end

end  # module
