-- llama.cpp HTTP backend for lua-llama-interface.
-- Targets the OpenAI-compatible chat completion endpoint exposed by
-- llama.cpp's server.

local https = require("https")
local json = require("./lunajson/lunajson")

local LlamaCpp = {}
LlamaCpp.__index = LlamaCpp

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function LlamaCpp.new(options)
    options = options or {}

    return setmetatable({
        host = options.host or "127.0.0.1",
        port = options.port or 50006,
        path = options.path or "/v1/chat/completions",
        model = options.model,
        user_agent = options.user_agent or "lua-llama-interface/0.1",
    }, LlamaCpp)
end

function LlamaCpp:_request(method, path, body, callback)
    local chunks = {}
    local completed = false

    local function finish(result, err, metadata)
        if completed then
            return
        end
        completed = true
        callback(result, err, metadata)
    end

    local encoded_body = body and json.encode(body) or nil
    local headers = {
        ["User-Agent"] = self.user_agent,
        ["Accept"] = "application/json",
        ["Connection"] = "close",
    }

    if encoded_body then
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#encoded_body)
    end

    local ok, req_or_error = pcall(function()
        return https.request({
            host = self.host,
            port = self.port,
            path = path,
            method = method,
            headers = headers,
        }, function(res)
            local status = tonumber(res.statusCode or res.code or 0)

            res:on("data", function(chunk)
                chunks[#chunks + 1] = chunk
            end)

            res:on("end", function()
                local response_body = table.concat(chunks)
                local metadata = {
                    status_code = status,
                    response_bytes = #response_body,
                }

                if status < 200 or status >= 300 then
                    finish(nil, string.format(
                        "llama.cpp HTTP %d: %s",
                        status,
                        trim(response_body):sub(1, 1000)
                    ), metadata)
                    return
                end

                if response_body == "" then
                    finish(nil, "llama.cpp returned an empty response", metadata)
                    return
                end

                local decoded_ok, decoded = pcall(json.decode, response_body)
                if not decoded_ok then
                    finish(nil,
                        "Unable to decode llama.cpp JSON response: "
                            .. tostring(decoded),
                        metadata)
                    return
                end

                finish(decoded, nil, metadata)
            end)
        end)
    end)

    if not ok then
        finish(nil,
            "Unable to create llama.cpp request: "
                .. tostring(req_or_error))
        return
    end

    req_or_error:on("error", function(err)
        finish(nil, "llama.cpp request error: " .. tostring(err))
    end)

    if encoded_body then
        req_or_error:write(encoded_body)
        req_or_error:finish()
    else
        req_or_error:finish()
    end
end

function LlamaCpp:status(callback)
    self:_request("GET", "/health", nil, function(result, err, metadata)
        if err then
            callback(nil, err, metadata)
            return
        end

        callback({
            ready = true,
            response = result,
        }, nil, metadata)
    end)
end

function LlamaCpp:chat(messages, options, callback)
    options = options or {}

    local body = {
        messages = messages,
        stream = false,
    }

    if self.model then
        body.model = self.model
    end

    local passthrough = {
        temperature = true,
        top_p = true,
        top_k = true,
        max_tokens = true,
        seed = true,
        stop = true,
        response_format = true,
    }

    for key in pairs(passthrough) do
        if options[key] ~= nil then
            body[key] = options[key]
        end
    end

    self:_request("POST", self.path, body, function(result, err, metadata)
        if err then
            callback(nil, err, metadata)
            return
        end

        local choice = result.choices and result.choices[1]
        if not choice or not choice.message then
            callback(nil,
                "llama.cpp response did not contain a chat message",
                metadata)
            return
        end

        local usage = result.usage or {}
        metadata = metadata or {}
        metadata.model = result.model
        metadata.prompt_tokens = usage.prompt_tokens
        metadata.completion_tokens = usage.completion_tokens
        metadata.total_tokens = usage.total_tokens

        callback(choice.message, nil, metadata)
    end)
end

return LlamaCpp
