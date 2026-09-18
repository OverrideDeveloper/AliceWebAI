-- memory_search.lua
-- Semantic memory search tool for Alice.

local M = {}

local MemoryClient = require("./memory_client")

function M.search(arguments, callback)

    if type(arguments) ~= "table" then
        arguments = {}
    end

    local query =
        tostring(
            arguments.query or ""
        )

    if query:match("^%s*$") then
        callback(
            "Error: memory search query is required",
            nil
        )
        return
    end

    local count =
        tonumber(
            arguments.count or 5
        )

    if not count then
        count = 5
    end

    count = math.floor(count)

    if count < 1 then
        count = 1
    elseif count > 10 then
        count = 10
    end

    local category =
        arguments.category

    MemoryClient.search(
        query,
        count,
        category,
        function(result, err)

            if err then
                callback(
                    "Error searching Alice memory: "
                        .. tostring(err),
                    nil
                )
                return
            end

            local results =
                result.results or {}

            if #results == 0 then
                callback(
                    "No relevant memories were found.",
                    nil
                )
                return
            end

            local output = {
                "Relevant Alice memories:"
            }

            for i, memory in
                ipairs(results) do

                table.insert(
                    output,
                    string.format(
                        "\n%d. %s",
                        i,
                        tostring(
                            memory.content or ""
                        )
                    )
                )

                local metadata =
                    memory.metadata or {}

                if metadata.source then
                    table.insert(
                        output,
                        "   Source: "
                            .. tostring(
                                metadata.source
                            )
                    )
                end

                if metadata.category then
                    table.insert(
                        output,
                        "   Category: "
                            .. tostring(
                                metadata.category
                            )
                    )
                end

                if memory.distance then
                    table.insert(
                        output,
                        "   Distance: "
                            .. tostring(
                                memory.distance
                            )
                    )
                end
            end

            callback(
                table.concat(output, "\n"),
                nil
            )
        end
    )
end

M.definition = {
    type = "function",

    ["function"] = {
        name = "memory_search",

        description =
            "Search Alice's long-term semantic memory. "
            .. "Use this when information from previous conversations, "
            .. "stored notes, projects, decisions, or other remembered "
            .. "context may be relevant to the user's request.",

        parameters = {
            type = "object",

            properties = {
                query = {
                    type = "string",

                    description =
                        "A natural-language description of the information "
                        .. "to retrieve from Alice's long-term memory."
                },

                count = {
                    type = "integer",

                    description =
                        "Number of memories to retrieve, from 1 to 10. "
                        .. "Defaults to 5."
                },

                category = {
                    type = "string",

                    description =
                        "Optional memory category filter."
                }
            },

            required = {
                "query"
            }
        }
    }
}

return M