local LlamaInterface = require("./llama_interface")
local LlamaCpp = require("./backends.llama_cpp")

local llama = LlamaInterface.new({
    backend = LlamaCpp.new({
        host = "127.0.0.1",
        port = 50006,
    }),

    on_event = function(event)
        print("[llama] " .. tostring(event.event))
    end,
})

llama:status(function(status, err)
    if err then
        print("Backend unavailable: " .. tostring(err))
        return
    end

    print("Backend ready")

    llama:chat({
        {
            role = "user",
            content = "Say hello from llama.cpp.",
        },
    }, {
        temperature = 0.7,
        max_tokens = 64,
    }, function(message, chat_err, metadata)
        if chat_err then
            print("Inference failed: " .. tostring(chat_err))
            return
        end

        print(message.content)
        print("Generated tokens: "
            .. tostring(metadata and metadata.completion_tokens or "unknown"))
    end)
end)
