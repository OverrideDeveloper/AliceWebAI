-- Alice Web AI
-- Regression tests for sequential TaskManager execution and failure handling.
-- Lua 5.1 compatible.

local TaskManager = require("../task_manager")

local executed = {}
local report
local error_value

TaskManager.run({
    calls = {
        {name = "first_tool", arguments = {value = 1}},
        {name = "failing_tool", arguments = {value = 2}},
        {name = "last_tool", arguments = {value = 3}},
    },
}, function(result, err)
    report = result
    error_value = err
end, function(name, arguments, callback)
    executed[#executed + 1] = name

    if name == "failing_tool" then
        callback(nil, {
            category = "test_failure",
            message = "Expected test failure",
        })
        return
    end

    callback({received = arguments.value}, nil)
end)

assert(error_value == nil, "A batch with individual failures should return a report")
assert(report ~= nil, "TaskManager should return a report")
assert(report.total == 3 and report.completed == 3)
assert(report.succeeded == 2 and report.failed == 1)
assert(table.concat(executed, ",") == "first_tool,failing_tool,last_tool",
    "Calls must run in order and continue after a failure")
assert(report.results[1].status == "success")
assert(report.results[1].result.received == 1)
assert(report.results[2].status == "failed")
assert(report.results[2].error.category == "test_failure")
assert(report.results[3].status == "success")
assert(report.results[3].result.received == 3)

local nested_report
TaskManager.run({
    calls = {
        {name = "task_manager", arguments = {calls = {}}},
        {name = "last_tool", arguments = {}},
    },
}, function(result, err)
    nested_report = result
    assert(err == nil)
end, function(name, arguments, callback)
    callback("executed", nil)
end)

assert(nested_report.results[1].status == "failed",
    "Nested TaskManager calls must be rejected")
assert(nested_report.results[2].status == "success",
    "Rejecting a nested call must not stop later calls")

local invalid_result
TaskManager.run({calls = {}}, function(result, err)
    assert(result == nil)
    invalid_result = err
end, function()
    error("Executor must not run for an invalid batch")
end)

assert(invalid_result.category == "invalid_request")

print("task_manager.lua tests passed")
