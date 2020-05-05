using ContextVariables
using Test

@testset "ContextVariables.jl" begin
    ok = Ref(0)
    @sync @async begin
        with_variables() do
            context_storage(:mykey, "hello")
            @test context_storage(:mykey) == "hello"
            ok[] += 1
            @async begin
                @test context_storage(:mykey) == "hello"
                ok[] += 1
            end
        end
    end
    @test ok[] == 2
end
