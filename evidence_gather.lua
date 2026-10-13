-- Alice Web AI
-- Local dataset focused evidence retrieval adapter.
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
    local term_find = trim(arguments.term_find)
    local index = tonumber(arguments.index)

    if corpus == "" then
        return nil, "EvidenceGather requires a corpus"
    end

    if term_find == "" then
        return nil, "EvidenceGather requires a term_find"
    end

    if not index then
        return nil, "EvidenceGather requires a record index"
    end

    index = math.floor(index)

    if index < 0 then
        return nil, "EvidenceGather index must not be negative"
    end

    local request = {
        corpus = corpus,
        query = term_find,
        index = index,
    }

    if arguments.max_bytes ~= nil then
        local max_bytes = tonumber(arguments.max_bytes)

        if not max_bytes then
            return nil, "EvidenceGather max_bytes must be an integer"
        end

        max_bytes = math.floor(max_bytes)

        if max_bytes < 1 then
            return nil, "EvidenceGather max_bytes must be greater than zero"
        end

        request.max_bytes = max_bytes
    end

    local timeout = M.config.timeout

    if arguments.timeout ~= nil then
        timeout = tonumber(arguments.timeout)

        if not timeout then
            return nil, "EvidenceGather timeout must be an integer"
        end

        timeout = math.floor(timeout)

        if timeout < 1 then
            return nil, "EvidenceGather timeout must be greater than zero"
        end
    end

    return request, nil, timeout
end

function M.gather(arguments, callback)
    if type(callback) ~= "function" then
        return nil, "EvidenceGather requires a callback"
    end

    local request, validation_error, timeout =
        validate(arguments)

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

    if request.max_bytes ~= nil then
        query = query .. "&max_bytes=" .. encode_component(request.max_bytes)
    end

    webcall.get(
        M.config.endpoint .. "/local_data/getevidence" .. query,
        {
            timeout = timeout,
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
            .. "a relevant record. The index identifies the record and "
            .. "term_find selects the structural evidence to return. The corpus "
            .. "must match the corpus used by EvidenceHunt. If the active "
            .. "corpus name is unknown, call EvidenceCorpus to discover it.",
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
                term_find = {
                    type = "string",
                    description =
                        "A word, term, or phrase to find by lexical matching "
                        .. "within the record selected by index. "
                        .. "Use text expected to occur in the record. "
                        .. "Do not provide a question, summary request, or instruction."
                },
                max_bytes = {
                    type = "integer",
                    description =
                        "Maximum evidence budget in bytes. Defaults to 512."
                },
                timeout = {
                    type = "integer",
                    description =
                        "HTTP request timeout in milliseconds. Defaults to 10000."
                },
            },
            required = {"corpus", "index", "term_find"},
        },
    },
}

return M
