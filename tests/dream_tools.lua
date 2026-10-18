-- Alice Web AI
-- Regression tests for bounded dream tool definitions and input validation.
-- Lua 5.1 / Luvit compatible.

local DreamTools = require("../dream_tools")

assert(DreamTools.trigger_definition["function"].name == "dream_trigger")
assert(DreamTools.summary_definition["function"].name == "dream_summary")

local normalized, err = DreamTools._validate_arguments({
    topic = "  Explore local-first AI  ",
    memory_search_query = " prior local AI discussions ",
})
assert(normalized, err)
assert(normalized.topic == "Explore local-first AI")
assert(normalized.memory_search_query == "prior local AI discussions")
assert(normalized.max_turns == 16)
assert(normalized.summary_interval == 8)

local capped = assert(DreamTools._validate_arguments({
    topic = "Topic", memory_search_query = "memory",
    max_turns = 100, summary_interval = 100,
}))
assert(capped.max_turns == DreamTools.hard_max_turns)
assert(capped.summary_interval == DreamTools.hard_max_turns)

local explicit = assert(DreamTools._validate_arguments({
    topic = "Topic", memory_search_query = "memory",
    max_turns = 5, summary_interval = 3,
}))
assert(explicit.max_turns == 5)
assert(explicit.summary_interval == 3)

local missing_topic, topic_error = DreamTools._validate_arguments({memory_search_query = "memory"})
assert(not missing_topic and topic_error:find("topic", 1, true))

local missing_query, query_error = DreamTools._validate_arguments({topic = "Topic"})
assert(not missing_query and query_error:find("memory_search_query", 1, true))

local bad_turns, turns_error = DreamTools._validate_arguments({
    topic = "Topic", memory_search_query = "memory", max_turns = 0,
})
assert(not bad_turns and turns_error:find("max_turns", 1, true))

assert(DreamTools._safe_dream_id("20261018T120000-123456"))
assert(not DreamTools._safe_dream_id("../conversation_history"))
assert(not DreamTools._safe_dream_id("bad/id"))
assert(#DreamTools._prompt_variants >= 5)

print("dream_tools.lua tests passed")
