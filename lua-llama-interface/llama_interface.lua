-- lua-llama-interface
-- A small Lua abstraction over LLM inference backends.
-- Lua 5.1 / Luvit compatible.

local LlamaInterface = {}
LlamaInterface.__index = LlamaInterface

function LlamaInterface.new(options)
    options = options or {}
    assert(options.backend, "A backend is required")

    return setmetatable({
        backend = options.backend,
        on_event = options.on_event,
    }, LlamaInterface)
end

function LlamaInterface:_emit(event)
    if self.on_event then
        self.on_event(event)
    end
end

function LlamaInterface:status(callback)
    self:_emit({ event = "backend_status_start" })

    self.backend:status(function(status, err, metadata)
        if err then
            self:_emit({
                event = "backend_status_failed",
                error = tostring(err),
                metadata = metadata,
            })
            callback(nil, err, metadata)
            return
        end

        self:_emit({
            event = "backend_status_complete",
            status = status,
            metadata = metadata,
        })
        callback(status, nil, metadata)
    end)
end

function LlamaInterface:chat(messages, options, callback)
    options = options or {}
    assert(type(messages) == "table", "messages must be a table")
    assert(type(callback) == "function", "callback is required")

    self:_emit({
        event = "inference_start",
        message_count = #messages,
    })

    self.backend:chat(messages, options, function(response, err, metadata)
        if err then
            self:_emit({
                event = "inference_failed",
                error = tostring(err),
                metadata = metadata,
            })
            callback(nil, err, metadata)
            return
        end

        self:_emit({
            event = "inference_complete",
            metadata = metadata,
        })
        callback(response, nil, metadata)
    end)
end

return LlamaInterface
