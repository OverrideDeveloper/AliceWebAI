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
                    status = "success",
                },
                {
                    tool_name = "memory_search",
                    status = "error",
                },
            },
        }
    )

assert(
    decorated:find("--- Tools executed ---", 1, true),
    "Tool provenance section must be appended"
)

assert(
    decorated:find("- web_search [success]", 1, true),
    "Successful tool execution must be visible"
)

assert(
    decorated:find("- memory_search [error]", 1, true),
    "Failed tool execution must be visible"
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

print("response_policy.lua tool provenance tests passed")
