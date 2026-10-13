-- Alice Web AI
-- Discover the corpus configured in the running local Data Engine.
-- Lua 5.1 / Luvit compatible.

local json = require("./json")
local webcall = require("./lua-webcall-model/webcall")

local M = {}

M.config = {
    endpoint = "http://127.0.0.1:60005",
    timeout = 10000,
}

function M.discover(arguments, callback)
    if type(callback) ~= "function" then
        return nil, "EvidenceCorpus requires a callback"
    end

    arguments = arguments or {}
    local timeout = M.config.timeout

    if arguments.timeout ~= nil then
        timeout = tonumber(arguments.timeout)

        if not timeout then
            callback(nil, {
                category = "invalid_request",
                message = "EvidenceCorpus timeout must be an integer",
            })
            return
        end

        timeout = math.floor(timeout)

        if timeout < 1 then
            callback(nil, {
                category = "invalid_request",
                message = "EvidenceCorpus timeout must be greater than zero",
            })
            return
        end
    end

    webcall.get(
        M.config.endpoint .. "/local_data/corpus",
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
                    message = "EvidenceCorpus request failed: " .. tostring(err),
                })
                return
            end

            if not response or type(response.body) ~= "string" then
                callback(nil, {
                    category = "invalid_response",
                    message = "EvidenceCorpus returned no response body",
                })
                return
            end

            local decoded, _, decode_error =
                json.decode(response.body, 1, nil)

            if type(decoded) ~= "table" then
                callback(nil, {
                    category = "invalid_response",
                    message = "Unable to decode EvidenceCorpus response: "
                        .. tostring(decode_error),
                })
                return
            end

            if type(decoded.corpus) ~= "string"
                or decoded.corpus:match("^%s*$") then
                callback(nil, {
                    category = "invalid_response",
                    message = "EvidenceCorpus response did not contain a corpus name",
                })
                return
            end

            callback({
                corpus = decoded.corpus,
            }, nil)
        end
    )
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "EvidenceCorpus",
        description =
            "Discover the name of the corpus currently configured in Alice's "
            .. "local Rust Data Engine. Call this before EvidenceHunt when "
            .. "the active corpus name is not already known, then pass the "
            .. "returned corpus value unchanged to EvidenceHunt and "
            .. "EvidenceGather. This reports the configured corpus name; it "
            .. "does not indicate whether preparation has finished.",
        parameters = {
            type = "object",
            properties = {
                timeout = {
                    type = "integer",
                    description =
                        "HTTP request timeout in milliseconds. Defaults to 10000."
                },
            },
        },
    },
}

return M
