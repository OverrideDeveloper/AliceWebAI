-- Alice Web AI
-- Regression tests for the EvidenceGather local data adapter.
-- Lua 5.1 compatible.

local calls = {}

package.loaded["./lua-webcall-model/webcall"] = {
    get = function(url, options, callback)
        calls.url = url
        calls.options = options

        callback({
            status = 200,
            body = '{"corpus":"wikipedia","query":"Ada Lovelace","index":123,"record":"<title>: Ada Lovelace"}',
        }, nil)
    end,
}

local EvidenceGather = require("../evidence_gather")

local result
local err

EvidenceGather.gather(
    {
        corpus = "wikipedia",
        index = 123,
        term_find = "Ada Lovelace",
    },
    function(value, failure)
        result = value
        err = failure
    end
)

assert(err == nil, "EvidenceGather should return no error")
assert(result.index == 123, "Record index should round-trip")
assert(
    calls.url == "http://127.0.0.1:60005/local_data/getevidence?corpus=wikipedia&i=123&query=Ada%20Lovelace",
    "EvidenceGather must translate term_find to the get evidence query parameter"
)

local invalid_error
EvidenceGather.gather(
    {
        corpus = "wikipedia",
        index = -1,
        term_find = "Ada Lovelace",
    },
    function(_, failure)
        invalid_error = failure
    end
)

assert(
    invalid_error and invalid_error.category == "invalid_request",
    "EvidenceGather must reject a negative index"
)

local missing_term_error
EvidenceGather.gather(
    {
        corpus = "wikipedia",
        index = 123,
    },
    function(_, failure)
        missing_term_error = failure
    end
)

assert(
    missing_term_error
        and missing_term_error.category == "invalid_request"
        and missing_term_error.message == "EvidenceGather requires a term_find",
    "EvidenceGather must require term_find"
)

print("evidence_gather.lua tests passed")
