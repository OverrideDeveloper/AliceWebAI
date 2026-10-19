-- Alice Web AI
-- Regression tests for platform-independent tool execution provenance.
-- Lua 5.1 compatible.

local ResponsePolicy = require("../response_policy")

local decorated =
    ResponsePolicy.decorate(
        "The answer.",
        {
            tool_calls = {
                {
                    tool_name = "web_search",
                },
                {
                    tool_name = "memory_search",
                },
            },
        }
    )

assert(
    decorated:find("--- Tool execution ---", 1, true),
    "Tool provenance section must be appended"
)

assert(
    decorated:find("- web_search", 1, true),
    "Successful tool execution must be visible"
)

assert(
    decorated:find("- memory_search", 1, true),
    "Failed tool execution must be visible"
)

local detailed =
    ResponsePolicy.decorate(
        "The answer.",
        {
            tool_calls = {
                {
                    tool_name = "EvidenceGather",
                    arguments = {
                        corpus = "wikipedia",
                        index = 13928,
                        query = "Nikola Tesla",
                        options = {
                            verbose = false,
                            tags = {"person", "scientist"},
                        },
                    },
                },
            },
        }
    )

assert(
    detailed:find('  corpus: "wikipedia"', 1, true),
    "Tool argument strings must be rendered"
)

assert(
    detailed:find("  index: 13928", 1, true),
    "Tool argument numbers must be rendered"
)

assert(
    detailed:find('  query: "Nikola Tesla"', 1, true),
    "Tool argument query must be rendered"
)

assert(
    detailed:find('  options: {tags: ["person", "scientist"], verbose: false}', 1, true),
    "Nested tool arguments must be rendered deterministically"
)

local plain =
    ResponsePolicy.decorate(
        "No tools were needed.",
        {}
    )

assert(
    not plain:find("--- Tools executed ---", 1, true),
    "Tool provenance must not be appended when no tools executed"
)

local dream_footer =
    ResponsePolicy.decorate(
        "The dream concluded.",
        {
            tool_calls = {
                {
                    tool_name = "dream_trigger",
                    arguments = {max_turns = 12},
                    display_result = {
                        dream_id = "20261018T212057-303824",
                        status = "completed",
                        turns_completed = 12,
                    },
                },
            },
        }
    )

assert(
    dream_footer:find('    dream_id: "20261018T212057-303824"', 1, true),
    "Dream identifier returned by the tool must be visible in the execution footer"
)
assert(
    dream_footer:find('    status: "completed"', 1, true),
    "Dream status must be visible alongside its identifier"
)
assert(
    dream_footer:find("    turns_completed: 12", 1, true),
    "Completed dream turn count must be visible alongside its identifier"
)

print("response_policy.lua tool provenance tests passed")
