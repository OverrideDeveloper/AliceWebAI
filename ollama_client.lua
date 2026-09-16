-- ollama_client.lua
-- Asynchronous Luvit HTTP client for Ollama.
-- Lua 5.1 compatible.
--
-- The web version of Alice must not block the Luvit event loop while
-- waiting for Ollama. call() therefore uses a callback:
--
--     OllamaClient.call(system_prompt, history, function(response, err)
--         ...
--     end)

local http = require("http")
local json = require("json")

local OllamaClient = {}

OllamaClient.config = {
    model = "gemma4:26b",
    chat_endpoint = "http://127.0.0.1:11434/api/chat",
    timeout = 120,
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

    -- Remove remaining non-ASCII bytes.
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

            table.insert(context, copied)
        end
    end

    return context
end

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

local function decode_response(response_text)
    local decoded, _, decode_error =
        json.decode(response_text, 1, nil)

    if not decoded then
        return nil,
            "Unable to decode Ollama response: " ..
            tostring(decode_error)
    end

    if decoded.error then
        return nil,
            "Ollama error: " ..
            tostring(decoded.error)
    end

    if not decoded.message then
        return nil,
            "Ollama response did not contain a message"
    end

    return decoded, nil
end

local function make_request(url, payload, callback)
    local host, port, path = parse_endpoint(url)

    if not host then
        callback(nil, "Invalid Ollama endpoint: " .. tostring(url))
        return
    end

    local completed = false
    local response_data = {}

    local function finish(response, err)
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
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#payload),
            ["Connection"] = "close",
        },
    }

    local ok, req_or_error = pcall(function()
        return http.request(request_options, function(res)

            local status_code = tonumber(res.statusCode or 0)

            res:on("data", function(chunk)
                response_data[#response_data + 1] = chunk
            end)

            res:on("end", function()
                local body = table.concat(response_data)

                if status_code < 200 or status_code >= 300 then
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
                    finish(nil, "Ollama returned an empty response")
                    return
                end

                finish(body, nil)
            end)

        end)
    end)

    if not ok then
        finish(
            nil,
            "Unable to create Ollama HTTP request: " ..
            tostring(req_or_error)
        )
        return
    end

    local req = req_or_error

    req:on("error", function(err)
        finish(
            nil,
            "Ollama request error: " ..
            tostring(err)
        )
    end)

    req:setTimeout(
        OllamaClient.config.timeout * 1000,
        function()
            finish(
                nil,
                "Ollama request timed out after " ..
                tostring(OllamaClient.config.timeout) ..
                " seconds"
            )

            req:destroy()
        end
    )

    -- Start the asynchronous request.
    req:done(payload)
end

function OllamaClient.call(system_prompt, conversation_history, callback)
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

    local context = build_context(conversation_history)

    for _, message in ipairs(context) do
        table.insert(messages, message)
    end

    local payload = {
        model = OllamaClient.config.model,
        messages = messages,
        stream = false,
    }

    local json_payload = json.encode(payload)

    if not json_payload then
        callback(
            nil,
            "Unable to encode Ollama request"
        )
        return
    end

    make_request(
        OllamaClient.config.chat_endpoint,
        json_payload,
        function(response_text, request_error)

            if request_error then
                callback(nil, request_error)
                return
            end

            local decoded, response_error =
                decode_response(response_text)

            if not decoded then
                callback(nil, response_error)
                return
            end

            local content =
                decoded.message.content or ""

            if content == "" then
                callback(nil, "No response from model")
                return
            end

            callback(
                ascii_sanitize(content),
                nil
            )
        end
    )
end

function OllamaClient.set_model(model_name)
    OllamaClient.config.model = model_name
    return true
end

function OllamaClient.set_chat_endpoint(endpoint_url)
    OllamaClient.config.chat_endpoint = endpoint_url
    return true
end

function OllamaClient.get_config()
    return OllamaClient.config
end

return OllamaClient