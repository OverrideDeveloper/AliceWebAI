-- Alice Web AI
--
-- Copyright (C) 2026 Override Development
--
-- This file is part of Alice Web AI.
--
-- Alice Web AI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- <https://www.gnu.org/licenses/>.

-- ollama_client.lua
-- Asynchronous Luvit HTTP client for Ollama.
-- Lua 5.1 compatible.
--
-- Supports Ollama tool calling through asynchronous tool rounds.

local http = require("http")
local json = require("json")

local MemorySearch = require("./memory_search")
local MemoryStore = require("./memory_store")
local CurrentTime = require("./current_time")

local OllamaClient = {}

OllamaClient.config = {
    model = "gemma4:26b",
    endpoint = "http://127.0.0.1:11434/api/generate",
    chat_endpoint = "http://127.0.0.1:11434/api/chat",
    timeout = 120,
    max_tool_rounds = 4,
}

local ToolHandlers = {
    memory_store = function(arguments, callback)
        MemoryStore.store(
            arguments,
            callback,
            "web"
        )
    end,
    memory_search = function(arguments, callback)
        MemorySearch.search(
            arguments,
            callback
        )
    end,
    current_time = CurrentTime.current_time
}


local function ascii_sanitize(text)
    text = tostring(text or "")

    local replacements = {
        ["\226\128\152"] = "'",
        ["\226\128\153"] = "'",
        ["\226\128\156"] = '"',
        ["\226\128\157"] = '"',
        ["\226\128\147"] = "-",
        ["\226\128\148"] = "-",
        ["\226\128\166"] = "...",

        ["\195\169"] = "e",
        ["\195\168"] = "e",
        ["\195\170"] = "e",
        ["\195\171"] = "e",

        ["\195\160"] = "a",
        ["\195\162"] = "a",
        ["\195\164"] = "a",

        ["\195\185"] = "u",
        ["\195\187"] = "u",
        ["\195\188"] = "u",

        ["\195\180"] = "o",
        ["\195\182"] = "o",

        ["\195\172"] = "i",
        ["\195\174"] = "i",
        ["\195\175"] = "i",

        ["\195\167"] = "c",
        ["\195\177"] = "n",
        ["\195\189"] = "y",
        ["\195\191"] = "y",
    }

    for encoded, replacement in pairs(replacements) do
        text = text:gsub(encoded, replacement)
    end

    text = text:gsub("[\128-\255]", "?")

    return text
end


local function build_context(history)
    local context = {}

    for _, message in ipairs(history or {}) do
        if message.role and message.content then

            local copied = {
                role = message.role,
                content = message.content,
            }

            if message.tool_calls then
                copied.tool_calls = message.tool_calls
            end

            if message.tool_name then
                copied.tool_name = message.tool_name
            end

            if message.tool_call_id then
                copied.tool_call_id =
                    message.tool_call_id
            end

            table.insert(
                context,
                copied
            )
        end
    end

    return context
end


local function parse_endpoint(endpoint)
    local host, port, path

    host, port, path =
        endpoint:match(
            "^http://([^:/]+):(%d+)(/.*)$"
        )

    if host and port and path then
        return host, tonumber(port), path
    end

    host, path =
        endpoint:match(
            "^http://([^/]+)(/.*)$"
        )

    if host and path then
        return host, 80, path
    end

    host =
        endpoint:match(
            "^http://([^/:]+)$"
        )

    if host then
        return host, 80, "/"
    end

    return nil, nil, nil
end


local function decode_response(response_text)
    local decoded, _, decode_error =
        json.decode(
            response_text,
            1,
            nil
        )

    if not decoded then
        return nil,
            "Unable to decode Ollama response: "
                .. tostring(decode_error)
    end

    if decoded.error then
        return nil,
            "Ollama error: "
                .. tostring(decoded.error)
    end

    if not decoded.message then
        return nil,
            "Ollama response did not contain a message"
    end

    return decoded, nil
end


local function make_request(
    url,
    payload,
    callback
)
    local host, port, path =
        parse_endpoint(url)

    if not host then
        callback(
            nil,
            "Invalid Ollama endpoint: "
                .. tostring(url)
        )
        return
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

    local request_options = {
        host = host,
        port = port,
        path = path,
        method = "POST",

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
                request_options,
                function(res)

                    local status_code =
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

                            local body =
                                table.concat(
                                    response_data
                                )

                            if status_code < 200 or
                               status_code >= 300 then

                                finish(
                                    nil,
                                    string.format(
                                        "Ollama HTTP %d: %s",
                                        status_code,
                                        body
                                    )
                                )

                                return
                            end

                            if body == "" then
                                finish(
                                    nil,
                                    "Ollama returned an empty response"
                                )
                                return
                            end

                            finish(
                                body,
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
            "Unable to create Ollama HTTP request: "
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
                "Ollama request error: "
                    .. tostring(err)
            )
        end
    )

    req:setTimeout(
        OllamaClient.config.timeout * 1000,
        function()

            finish(
                nil,
                "Ollama request timed out after "
                    .. tostring(
                        OllamaClient.config.timeout
                    )
                    .. " seconds"
            )

            req:destroy()
        end
    )

    req:done(payload)
end


local function decode_tool_arguments(
    arguments
)
    if type(arguments) == "table" then
        return arguments, nil
    end

    if type(arguments) ~= "string" then
        return nil,
            "Tool arguments were not an object "
                .. "or JSON string"
    end

    local decoded, _, decode_error =
        json.decode(
            arguments,
            1,
            nil
        )

    if not decoded then
        return nil,
            "Unable to decode tool arguments: "
                .. tostring(decode_error)
    end

    if type(decoded) ~= "table" then
        return nil,
            "Tool arguments must decode to an object"
    end

    return decoded, nil
end


local function execute_tool(
    tool_call,
    callback
)
    if type(tool_call) ~= "table" then
        callback(
            nil,
            "Malformed tool call"
        )
        return
    end

    local function_data =
        tool_call["function"]

    if type(function_data) ~= "table" then
        callback(
            nil,
            "Tool call has no function object"
        )
        return
    end

    local tool_name =
        function_data.name

    if type(tool_name) ~= "string"
       or tool_name == "" then

        callback(
            nil,
            "Tool call has no function name"
        )

        return
    end

    local arguments,
        argument_error =
        decode_tool_arguments(
            function_data.arguments or {}
        )

    if not arguments then
        callback(
            nil,
            argument_error
        )
        return
    end

    local tool_func =
        ToolHandlers[tool_name]

    if type(tool_func) ~= "function" then
        callback(
            nil,
            "Unknown tool: "
                .. tool_name
        )
        return
    end

    print(
        "[Tool call: "
            .. tool_name
            .. "]"
    )

    ----------------------------------------------------------------
    -- Asynchronous tools
    ----------------------------------------------------------------

    local asynchronous_tools = {
        memory_search = true,
        memory_store = true,
    }

    if asynchronous_tools[tool_name] then

        local ok, immediate_error =
            pcall(
                tool_func,
                arguments,
                function(result, err)

                    if err then
                        callback(
                            nil,
                            tostring(result or err)
                        )
                        return
                    end

                    callback(
                        result,
                        nil
                    )
                end
            )

        if not ok then
            callback(
                nil,
                "Exception while executing "
                    .. tool_name
                    .. ": "
                    .. tostring(immediate_error)
            )
        end

        return
    end

    ----------------------------------------------------------------
    -- Synchronous tools
    ----------------------------------------------------------------

    local ok, result =
        pcall(
            tool_func,
            arguments
        )

    if not ok then
        callback(
            nil,
            "Exception while executing "
                .. tool_name
                .. ": "
                .. tostring(result)
        )

        return
    end

    callback(
        result,
        nil
    )
end


local function get_tool_calls(
    message
)
    if type(message.tool_calls)
        ~= "table" then

        return {}
    end

    return message.tool_calls
end


local function make_tool_result_message(
    tool_call,
    result
)
    local function_data =
        tool_call["function"] or {}

    local message = {
        role = "tool",
        content = tostring(
            result or ""
        ),
    }

    if function_data.name then
        message.tool_name =
            function_data.name
    end

    if tool_call.id then
        message.tool_call_id =
            tool_call.id
    end

    return message
end


local function execute_tool_calls(
    tool_calls,
    index,
    messages,
    callback
)
    if index > #tool_calls then
        callback(nil)
        return
    end

    local tool_call =
        tool_calls[index]

    execute_tool(
        tool_call,
        function(result, err)

            if err then
                result =
                    "Tool error: "
                    .. tostring(err)
            end

            table.insert(
                messages,
                make_tool_result_message(
                    tool_call,
                    result
                )
            )

            execute_tool_calls(
                tool_calls,
                index + 1,
                messages,
                callback
            )
        end
    )
end


local function call_round(
    system_prompt,
    messages,
    tools,
    round,
    callback
)
    local payload = {
        model =
            OllamaClient.config.model,

        messages = messages,

        stream = false,
    }

    if tools and #tools > 0 then
        payload.tools = tools
    end

    local json_payload,
        encode_error =
        json.encode(payload)

    if not json_payload then
        callback(
            nil,
            "Unable to encode Ollama request: "
                .. tostring(encode_error)
        )
        return
    end

    print(
        string.format(
            "[Ollama tool round %d]",
            round
        )
    )

    make_request(
        OllamaClient.config.chat_endpoint,
        json_payload,
        function(
            response_text,
            request_error
        )

            if request_error then
                callback(
                    nil,
                    request_error
                )
                return
            end

            local decoded,
                response_error =
                decode_response(
                    response_text
                )

            if not decoded then
                callback(
                    nil,
                    response_error
                )
                return
            end

            local assistant_message =
                decoded.message

            local tool_calls =
                get_tool_calls(
                    assistant_message
                )

            -- Normal final answer.
            if #tool_calls == 0 then

                local content =
                    assistant_message.content
                    or ""

                if content == "" then
                    callback(
                        nil,
                        "No response from model"
                    )
                    return
                end

                callback(
                    ascii_sanitize(content),
                    nil
                )

                return
            end

            -- Preserve Ollama's assistant
            -- tool-call message.
            table.insert(
                messages,
                assistant_message
            )

            -- Execute each tool asynchronously,
            -- then continue with another Ollama
            -- round.
            execute_tool_calls(
                tool_calls,
                1,
                messages,
                function(tool_error)

                    if tool_error then
                        callback(
                            nil,
                            tool_error
                        )
                        return
                    end

                    if round >=
                        (OllamaClient.config.max_tool_rounds
                         or 4) then

                        callback(
                            nil,
                            "Maximum tool-call rounds exceeded"
                        )

                        return
                    end

                    call_round(
                        system_prompt,
                        messages,
                        tools,
                        round + 1,
                        callback
                    )
                end
            )
        end
    )
end


function OllamaClient.call(
    system_prompt,
    conversation_history,
    tools,
    callback
)
    if type(callback) ~= "function" then
        return nil,
            "OllamaClient.call requires a callback"
    end

    local messages = {
        {
            role = "system",
            content = system_prompt,
        },
    }

    local context =
        build_context(
            conversation_history
        )

    for _, message in
        ipairs(context) do

        table.insert(
            messages,
            message
        )
    end

    call_round(
        system_prompt,
        messages,
        tools,
        1,
        callback
    )
end


function OllamaClient.set_model(
    model_name
)
    OllamaClient.config.model =
        model_name

    return true
end


function OllamaClient.set_chat_endpoint(
    endpoint_url
)
    OllamaClient.config.chat_endpoint =
        endpoint_url

    return true
end


function OllamaClient.get_config()
    return OllamaClient.config
end


return OllamaClient