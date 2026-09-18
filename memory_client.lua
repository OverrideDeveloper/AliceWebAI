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

-- memory_client.lua
-- Asynchronous HTTP client for Alice's local Chroma memory service.
-- Lua 5.1 / Luvit compatible.

local http = require("http")
local json = require("json")

local MemoryClient = {}

MemoryClient.config = {
    endpoint = "http://127.0.0.1:8090",
    timeout = 10,
}

local function parse_endpoint(endpoint)
    local host, port, path

    host, port, path =
        endpoint:match("^http://([^:/]+):(%d+)(/.*)$")

    if host and port and path then
        return host, tonumber(port), path
    end

    host, path =
        endpoint:match("^http://([^/]+)(/.*)$")

    if host and path then
        return host, 80, path
    end

    host =
        endpoint:match("^http://([^/:]+)$")

    if host then
        return host, 80, "/"
    end

    return nil, nil, nil
end

local function request(
    method,
    path,
    body,
    callback
)
    local url =
        MemoryClient.config.endpoint ..
        path

    local host, port, request_path =
        parse_endpoint(url)

    if not host then
        callback(
            nil,
            "Invalid memory service endpoint: "
                .. tostring(url)
        )
        return
    end

    local payload = ""

    if body then
        payload = json.encode(body)

        if not payload then
            callback(
                nil,
                "Unable to encode memory request"
            )
            return
        end
    end

    local completed = false
    local response_data = {}

    local function finish(
        response,
        err
    )
        if completed then
            return
        end

        completed = true
        callback(response, err)
    end

    local options = {
        host = host,
        port = port,
        path = request_path,
        method = method,

        headers = {
            ["Content-Type"] =
                "application/json",

            ["Content-Length"] =
                tostring(#payload),

            ["Connection"] =
                "close",
        },
    }

    local ok, req_or_error =
        pcall(function()
            return http.request(
                options,
                function(res)

                    local status =
                        tonumber(
                            res.statusCode or 0
                        )

                    res:on(
                        "data",
                        function(chunk)
                            response_data[
                                #response_data + 1
                            ] = chunk
                        end
                    )

                    res:on(
                        "end",
                        function()

                            local raw =
                                table.concat(
                                    response_data
                                )

                            if status < 200 or
                               status >= 300 then

                                finish(
                                    nil,
                                    string.format(
                                        "Memory service HTTP %d: %s",
                                        status,
                                        raw
                                    )
                                )

                                return
                            end

                            if raw == "" then
                                finish(
                                    nil,
                                    "Memory service returned empty response"
                                )
                                return
                            end

                            local decoded,
                                _,
                                decode_error =
                                json.decode(
                                    raw,
                                    1,
                                    nil
                                )

                            if not decoded then
                                finish(
                                    nil,
                                    "Unable to decode memory service response: "
                                        .. tostring(
                                            decode_error
                                        )
                                )
                                return
                            end

                            finish(
                                decoded,
                                nil
                            )
                        end
                    )
                end
            )
        end)

    if not ok then
        finish(
            nil,
            "Unable to create memory request: "
                .. tostring(req_or_error)
        )
        return
    end

    local req = req_or_error

    req:on(
        "error",
        function(err)
            finish(
                nil,
                "Memory request error: "
                    .. tostring(err)
            )
        end
    )

    req:setTimeout(
        MemoryClient.config.timeout * 1000,
        function()

            finish(
                nil,
                "Memory request timed out after "
                    .. tostring(
                        MemoryClient.config.timeout
                    )
                    .. " seconds"
            )

            req:destroy()
        end
    )

    req:done(payload)
end

function MemoryClient.search(
    query,
    count,
    category,
    callback
)
    if type(callback) ~= "function" then
        return nil,
            "MemoryClient.search requires a callback"
    end

    request(
        "POST",
        "/memory/search",
        {
            query = query,
            count = count or 5,
            category = category,
        },
        callback
    )
end

function MemoryClient.store(
    content,
    source,
    category,
    metadata,
    callback
)
    if type(callback) ~= "function" then
        return nil,
            "MemoryClient.store requires a callback"
    end

    request(
        "POST",
        "/memory/store",
        {
            content = content,
            source = source or "conversation",
            category = category or "general",
            metadata = metadata or {},
        },
        callback
    )
end

function MemoryClient.delete(
    memory_id,
    callback
)
    if type(callback) ~= "function" then
        return nil,
            "MemoryClient.delete requires a callback"
    end

    request(
        "POST",
        "/memory/delete",
        {
            id = memory_id,
        },
        callback
    )
end

function MemoryClient.status(callback)
    if type(callback) ~= "function" then
        return nil,
            "MemoryClient.status requires a callback"
    end

    request(
        "GET",
        "/memory/status",
        nil,
        callback
    )
end

return MemoryClient