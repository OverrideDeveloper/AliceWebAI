# lua-llama-interface

A Lua based interface for llama.cpp and future LLM inference backends.

The project provides a small backend boundary between a Lua application and an
LLM inference system. The first backend targets the OpenAI-compatible HTTP API
served by llama.cpp.

## Architecture

```
Lua application
      |
      v
lua-llama-interface
      |
      +---- llama.cpp HTTP backend
      |
      +---- future inference backend
```

The interface keeps the agent runtime outside the inference backend.
Conversation state, tools, provenance, authorization, and epistemic logic
belong to the calling application.

## JSON

The interface vendors the MIT-licensed lunajson implementation under
`./lunajson` and uses it directly for JSON encoding and decoding. This keeps
the interface self-contained and avoids requiring a separate JSON dependency
at runtime.

The vendored source comes from:

`https://github.com/OverrideDeveloper/lunajson`

The JSON implementation provides `encode` and `decode`, with streaming/SAX
support available through the vendored module as well.

## MVP

The current MVP provides:

- a backend-neutral `LlamaInterface`;
- a llama.cpp HTTP backend;
- asynchronous chat completion;
- backend health/status checks;
- structured lifecycle events;
- basic inference metadata;
- explicit backend errors rather than synthesized fallback explanations.

The llama.cpp backend expects a running server with its OpenAI-compatible
`/v1/chat/completions` endpoint and `/health` endpoint.

The default local development endpoint is `127.0.0.1:50006`. Port `50006`
is in the IANA dynamic/private port range and does not collide with
AliceWebAI's `8080` default. Applications may override both host and port at
runtime.

## Example

Start a llama.cpp server separately, then run:

```lua
local LlamaInterface = require("./llama_interface")
local LlamaCpp = require("./backends.llama_cpp")

local llama = LlamaInterface.new({
    backend = LlamaCpp.new({
        host = "127.0.0.1",
        port = 50006,
    }),
})

llama:chat({
    {
        role = "user",
        content = "Hello.",
    },
}, {}, function(message, err, metadata)
    if err then
        print(err)
        return
    end

    print(message.content)
end)
```

See `example.lua` for lifecycle event logging and health checking.

## Backend contract

A backend currently implements:

- `status(callback)`
- `chat(messages, options, callback)`

The contract is intentionally small. Future backends can adapt a different
inference server or local inference library without requiring the application
to change its model-facing code.

## Observability

The interface reports lifecycle events such as:

- `backend_status_start`
- `backend_status_complete`
- `backend_status_failed`
- `inference_start`
- `inference_complete`
- `inference_failed`

These events describe execution state. They are not model reasoning or
chain-of-thought.

## Scope

This project is an interface layer, not an inference engine. It does not
download models, execute model weights, implement tokenization, or own agent
tool execution.

Runtime validation depends on a working Lua/Luvit environment and a running
llama.cpp server.
