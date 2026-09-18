-- memory_store.lua
-- Deliberate long-term memory storage tool for Alice.

local M = {}

local MemoryClient = require("./memory_client")

function M.store(arguments, callback)

    if type(arguments) ~= "table" then
        arguments = {}
    end

    local content =
        tostring(
            arguments.content or ""
        )

    if content:match("^%s*$") then
        callback(
            "Error: memory content is required",
            nil
        )
        return
    end

    local source =
        tostring(
            arguments.source or "conversation"
        )

    local category =
        tostring(
            arguments.category or "general"
        )

    MemoryClient.store(
        content,
        source,
        category,
        arguments.metadata or {},
        function(result, err)

            if err then
                callback(
                    "Error storing memory: "
                        .. tostring(err),
                    nil
                )
                return
            end

            local stored =
                result.stored or {}

            callback(
                "Memory stored successfully.\n"
                    .. "ID: "
                    .. tostring(stored.id or ""),
                nil
            )
        end
    )
end

M.definition = {
    type = "function",

    ["function"] = {
        name = "memory_store",

        description =
            "Store information in Alice's long-term semantic memory. "
            .. "Use this when the user explicitly asks Alice to remember "
            .. "something, or when a durable project fact or decision "
            .. "should be preserved.",

        parameters = {
            type = "object",

            properties = {
                content = {
                    type = "string",

                    description =
                        "The information Alice should remember."
                },

                source = {
                    type = "string",

                    description =
                        "Where the memory came from, such as conversation, "
                        .. "note, document, or user."
                },

                category = {
                    type = "string",

                    description =
                        "A category such as architecture, project, "
                        .. "preference, campaign, or general."
                }
            },

            required = {
                "content"
            }
        }
    }
}

return M