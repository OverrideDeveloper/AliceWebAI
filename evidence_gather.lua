-- Alice Web AI
-- Local dataset focused evidence retrieval adapter.
-- Lua 5.1 / Luvit compatible.

local json = require("./json")
local webcall = require("webcall")

local M = {}

M.config = {
    endpoint = "http://127.0.0.1:60005",
    timeout = 10000,
    max_bytes = 512,
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
    local index = tonumber(arguments.index)

    if corpus == "" then
        return nil, "EvidenceGather requires a corpus"
    end

    if query == "" then
        return nil, "EvidenceGather requires a query"
    end

    if not index then
        return nil, "EvidenceGather requires a record index"
    end

    index = math.floor(index)

    if index < 0 then
        return nil, "EvidenceGather index must not be negative"
    end

    local max_bytes =
        tonumber(arguments.max_bytes or M.config.max_bytes)
        or M.config.max_bytes

    max_bytes = math.floor(max_bytes)

    if max_bytes < 1 then
        return nil, "EvidenceGather max_bytes must be greater than zero"
    end

    return {
        corpus = corpus,
        query = query,
        index = index,
        max_bytes = max_bytes,
    }, nil
end

function M.gather(arguments, callback)
    if type(callback) ~= "function" then
        return nil, "EvidenceGather requires a callback"
    end

    local request, validation_error = validate(arguments)

    if not request then
        callback(nil, {
            category = "invalid_request",
            message = validation_error,
        })
        return
    end

    local query =
        "?corpus=" .. encode_component(request.corpus)
        .. "&i=" .. encode_component(request.index)
        .. "&query=" .. encode_component(request.query)
        .. "&max_bytes=" .. encode_component(request.max_bytes)

    webcall.get(
        M.config.endpoint .. "/local_data/getevidence" .. query,
        {
            timeout = M.config.timeout,
            headers = {
                ["Accept"] = "application/json",
            },
        },
        function(response, err)
            if err then
                callback(nil, {
                    category = "local_data_unavailable",
                    message = "EvidenceGather request failed: "
                        .. tostring(err),
                })
                return
            end

            if not response or type(response.body) ~= "string" then
                callback(nil, {
                    category = "invalid_response",
                    message = "EvidenceGather returned no response body",
                })
                return
            end

            local decoded, _, decode_error =
                json.decode(response.body, 1, nil)

            if not decoded then
                callback(nil, {
                    category = "invalid_response",
                    message = "Unable to decode EvidenceGather response: "
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
        name = "EvidenceGather",
        description =
            "Retrieve bounded evidence from one specific authoritative "
            .. "local data record. Use this after EvidenceHunt identifies "
            .. "a relevant record. The index identifies the record and the "
            .. "query selects the structural evidence to return. The corpus "
            .. "must match the corpus used by EvidenceHunt.",
        parameters = {
            type = "object",
            properties = {
                corpus = {
                    type = "string",
                    description =
                        "Name of the local data corpus containing the record."
                },
                index = {
                    type = "integer",
                    description =
                        "Authoritative record index returned by EvidenceHunt."
                },
                query = {
                    type = "string",
                    description =
                        "Text used to select the structural evidence from the record."
                },
                max_bytes = {
                    type = "integer",
                    description =
                        "Maximum evidence budget in bytes. Defaults to 512."
                },
            },
            required = {"corpus", "index", "query"},
        },
    },
}

return M
