-- Alice Web AI
-- Local dataset evidence discovery adapter.
-- Lua 5.1 / Luvit compatible.

local json = require("./json")
local webcall = require("./lua-webcall-model/webcall")

local M = {}

M.config = {
    endpoint = "http://127.0.0.1:60005",
    timeout = 10000,
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function encode_component(value)
    return tostring(value or "")
        :gsub("[^%w%-_%.~]", function(character)
            return string.format("%%%02X", string.byte(character))
        end)
end

local function validate(arguments)
    arguments = arguments or {}

    local corpus = trim(arguments.corpus)
    local query = trim(arguments.query)

    if corpus == "" then
        return nil, "EvidenceHunt requires a corpus"
    end

    if query == "" then
        return nil, "EvidenceHunt requires a query"
    end

    local request = {
        corpus = corpus,
        query = query,
    }

    if arguments.record_limit ~= nil then
        local record_limit = tonumber(arguments.record_limit)

        if not record_limit then
            return nil, "EvidenceHunt record_limit must be an integer"
        end

        record_limit = math.floor(record_limit)

        if record_limit < 1 then
            return nil, "EvidenceHunt record_limit must be greater than zero"
        end

        request.record_limit = record_limit
    end

    if arguments.max_bytes ~= nil then
        local max_bytes = tonumber(arguments.max_bytes)

        if not max_bytes then
            return nil, "EvidenceHunt max_bytes must be an integer"
        end

        max_bytes = math.floor(max_bytes)

        if max_bytes < 1 then
            return nil, "EvidenceHunt max_bytes must be greater than zero"
        end

        request.max_bytes = max_bytes
    end

    return request, nil
end

function M.hunt(arguments, callback)
    if type(callback) ~= "function" then
        return nil, "EvidenceHunt requires a callback"
    end

    local request, validation_error = validate(arguments)

    if not request then
        callback(nil, {
            category = "invalid_request",
            message = validation_error,
        })
        return
    end

    local payload, encode_error = json.encode(request)

    if not payload then
        callback(nil, {
            category = "request_encoding_error",
            message = "Unable to encode EvidenceHunt request: "
                .. tostring(encode_error),
        })
        return
    end

    webcall.post(
        M.config.endpoint .. "/local_data/findevidence",
        payload,
        {
            timeout = M.config.timeout,
            headers = {
                ["Content-Type"] = "application/json",
                ["Accept"] = "application/json",
            },
        },
        function(response, err)
            if err then
                callback(nil, {
                    category = "local_data_unavailable",
                    message = "EvidenceHunt request failed: "
                        .. tostring(err),
                })
                return
            end

            if not response or type(response.body) ~= "string" then
                callback(nil, {
                    category = "invalid_response",
                    message = "EvidenceHunt returned no response body",
                })
                return
            end

            local decoded, _, decode_error =
                json.decode(response.body, 1, nil)

            if not decoded then
                callback(nil, {
                    category = "invalid_response",
                    message = "Unable to decode EvidenceHunt response: "
                        .. tostring(decode_error),
                })
                return
            end

            callback(decoded, nil)
        end
    )
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "EvidenceHunt",
        description =
            "Search a local data corpus for relevant records and return "
            .. "bounded evidence from the matches. Use this to discover "
            .. "which authoritative records may answer the current request. "
            .. "Each result includes an index that can be passed to "
            .. "EvidenceGather for more focused evidence. The corpus must "
            .. "be named explicitly.",
        parameters = {
            type = "object",
            properties = {
                corpus = {
                    type = "string",
                    description =
                        "Name of the local data corpus to search, such as wikipedia."
                },
                query = {
                    type = "string",
                    description =
                        "Text to search for in the local corpus."
                },
                record_limit = {
                    type = "integer",
                    description =
                        "Maximum number of matching records to return. Defaults to 5."
                },
                max_bytes = {
                    type = "integer",
                    description =
                        "Maximum evidence budget per returned record in bytes. Defaults to 512."
                },
            },
            required = {"corpus", "query"},
        },
    },
}

return M
