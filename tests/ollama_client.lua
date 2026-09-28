-- Alice Web AI
-- Regression tests for tool result serialization.
-- Lua 5.1 compatible.

local OllamaClient = require("../ollama_client")

local evidence = {
    corpus = "wikipedia",
    query = "Analytical Engine",
    results = {
        {
            index = 510,
            record = "<title>: Analytical engine\n<ns>: 0\n<id>: 1271",
        },
        {
            index = 537,
            record = "<title>: Ada Byron's notes on the analytical engine",
        },
    },
}

local serialized = OllamaClient._serialize_tool_result(evidence)

assert(
    serialized:find('"corpus":"wikipedia"', 1, true),
    "EvidenceHunt serialization must preserve the corpus"
)
assert(
    serialized:find('"query":"Analytical Engine"', 1, true),
    "EvidenceHunt serialization must preserve the query"
)
assert(
    serialized:find('"index":510', 1, true),
    "EvidenceHunt serialization must preserve record indexes"
)
assert(
    serialized:find('"record":"<title>: Analytical engine\\n<ns>: 0\\n<id>: 1271"', 1, true),
    "EvidenceHunt serialization must preserve bounded evidence records"
)
assert(
    not serialized:find('"title"', 1, true),
    "EvidenceHunt serialization must not project records through web-search fields"
)

print("ollama_client.lua tests passed")
