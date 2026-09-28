-- Alice Web AI
-- Regression tests for the EvidenceHunt local data adapter.
-- Lua 5.1 compatible.

local calls = {}

package.loaded["../lua-webcall-model/webcall"] = {
    post = function(url, body, options, callback)
        calls.url = url
        calls.body = body
        calls.options = options

        callback({
            status = 200,
            body = '{"corpus":"wikipedia","query":"Ada Lovelace","results":[{"index":123,"record":"<title>: Ada Lovelace"}]}',
        }, nil)
    end,
}

local EvidenceHunt = require("../evidence_hunt")

local result
local err

EvidenceHunt.hunt(
    {
        corpus = "wikipedia",
        query = "Ada Lovelace",
    },
    function(value, failure)
        result = value
        err = failure
    end
)

assert(err == nil, "EvidenceHunt should return no error")
assert(result.corpus == "wikipedia", "Corpus should round-trip")
assert(result.results[1].index == 123, "Record index should round-trip")
assert(
    calls.url == "http://127.0.0.1:60005/local_data/findevidence",
    "EvidenceHunt must call the find evidence endpoint"
)
assert(
    not calls.body:find('"record_limit"', 1, true),
    "EvidenceHunt should let the Rust API own the record-limit default"
)
assert(
    not calls.body:find('"max_bytes"', 1, true),
    "EvidenceHunt should let the Rust API own the evidence-budget default"
)

local invalid_error
EvidenceHunt.hunt(
    {
        corpus = "wikipedia",
    },
    function(_, failure)
        invalid_error = failure
    end
)

assert(
    invalid_error and invalid_error.category == "invalid_request",
    "EvidenceHunt must reject a missing query"
)

print("evidence_hunt.lua tests passed")
