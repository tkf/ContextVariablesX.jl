struct ContextPayloadLogger <: AbstractLogger
    logger::AbstractLogger
    ctxvars::Any
end

ContextPayloadLogger(logger::ContextPayloadLogger, ctxvars) =
    ContextPayloadLogger(logger.logger, ctxvars)

function _get_task_ctxvars()
    logger = current_logger()
    if logger isa ContextPayloadLogger
        return logger.ctxvars
    end
    return nothing
end

function with_task_ctxvars(f, ctx)
    @nospecialize
    return with_logger(f, ContextPayloadLogger(current_logger(), ctx))
end

# Forward actual logging interface:
Logging.handle_message(payload::ContextPayloadLogger, args...; kwargs...) =
    Logging.handle_message(payload.logger, args...; kwargs...)
Logging.shouldlog(payload::ContextPayloadLogger, args...) =
    Logging.shouldlog(payload.logger, args...)
Logging.min_enabled_level(payload::ContextPayloadLogger, args...) =
    Logging.min_enabled_level(payload.logger, args...)
Logging.catch_exceptions(payload::ContextPayloadLogger, args...) =
    Logging.catch_exceptions(payload.logger, args...)
