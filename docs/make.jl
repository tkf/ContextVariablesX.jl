using Documenter
using ContextVariables

makedocs(
    sitename = "ContextVariables",
    format = Documenter.HTML(),
    modules = [ContextVariables],
)

deploydocs(; repo = "github.com/tkf/ContextVariables.jl")
