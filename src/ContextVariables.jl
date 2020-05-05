module ContextVariables

export context_storage, with_variables

using Base.Meta: isexpr
using IRTools
using IRTools: @dynamo, IR, recurse!
using UUIDs: UUID

const CVKEY = UUID("30c48ab6-eb66-4e00-8274-c879a8246cdb")

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
    task_local_storage(CVKEY, Dict(kvs)) do
        propagate_variables(f)
    end
end

context_storage(key) = task_local_storage(CVKEY)[key]
context_storage(key, value) = task_local_storage(CVKEY)[key] = value

end # module
