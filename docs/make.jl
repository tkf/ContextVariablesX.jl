using Documenter
using ContextVariablesX

makedocs(
    sitename = "ContextVariablesX",
    format = Documenter.HTML(),
    modules = [ContextVariablesX],
)

deploydocs(; repo = "github.com/tkf/ContextVariablesX.jl", push_preview = true)
