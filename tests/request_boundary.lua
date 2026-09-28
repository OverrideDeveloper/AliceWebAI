-- Alice Web AI
-- Regression tests for request-scoped execution boundaries.
-- Lua 5.1 compatible.

local Observability = require("../observability")

local first =
    Observability.new_context({
        user_id = "test-user",
        provider = "test",
    })

local second =
    Observability.new_context({
        user_id = "test-user",
        provider = "test",
    })

assert(
    first.request_id ~= second.request_id,
    "Each request must receive a distinct request ID"
)

assert(
    first.closed == false,
    "A new request must begin open"
)

assert(
    second.closed == false,
    "A new request must not inherit terminal state"
)

assert(
    Observability.complete(first, "failure") == true,
    "The first completion must transition the request to terminal state"
)

assert(
    first.closed == true,
    "Completed request must be marked closed"
)

assert(
    Observability.complete(first, "success") == false,
    "A terminal request must not complete a second time"
)

assert(
    second.closed == false,
    "Completing one request must not close another request"
)

print("request boundary tests passed")
