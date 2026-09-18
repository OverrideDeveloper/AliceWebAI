-- Alice Web AI

-- Copyright (C) 2026 Override Development

-- This file is part of Alice Web AI.

-- Alice Web AI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--------------------------------------

-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
-----------------------------------------------

-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- https://www.gnu.org/licenses/.
-- memory_store.lua
-- Deliberate long-term memory storage tool for Alice.

local M = {}

local MemoryClient = require("./memory_client")

function M.store(arguments, callback, source)
    if type(arguments) ~= "table" then
        arguments = {}
    end

    local content =
        tostring(arguments.content or "")

    if content:match("^%s*$") then
        callback(
            "Error: memory content is required",
            nil
        )
        return
    end

    source =
        tostring(source or "unknown")

    local category =
        tostring(arguments.category or "general")

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

                category = {
                    type = "string",
                    description =
                        "A category such as architecture, project, "
                        .. "preference, or general."
                }
            },

            required = {
                "content"
            }
        }
    }
}

return M