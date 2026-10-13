-- Alice Web AI
-- Sequential tool-batch orchestration for Alice's Lua Middleware.
-- Lua 5.1 compatible.

local M = {}

M.max_calls = 8

function M.run(arguments, callback, execute)
    if type(callback) ~= "function" then
        return nil, "TaskManager requires a callback"
    end

    if type(execute) ~= "function" then
        callback(nil, {
            category = "invalid_configuration",
            message = "TaskManager requires a tool executor",
        })
        return
    end

    arguments = arguments or {}
    local calls = arguments.calls

    if type(calls) ~= "table" or #calls < 1 then
        callback(nil, {
            category = "invalid_request",
            message = "TaskManager requires a non-empty calls array",
        })
        return
    end

    if #calls > M.max_calls then
        callback(nil, {
            category = "invalid_request",
            message = "TaskManager accepts at most "
                .. tostring(M.max_calls) .. " calls",
        })
        return
    end

    local report = {
        total = #calls,
        completed = 0,
        succeeded = 0,
        failed = 0,
        results = {},
    }

    local function run_next(index)
        if index > #calls then
            callback(report, nil)
            return
        end

        local call = calls[index]
        local name = type(call) == "table" and call.name or nil
        local tool_arguments =
            type(call) == "table" and call.arguments or {}

        local function record_failure(message, details)
            report.results[#report.results + 1] = {
                index = index,
                name = type(name) == "string" and name or "",
                status = "failed",
                arguments = type(tool_arguments) == "table"
                    and tool_arguments or {},
                error = details or {
                    category = "invalid_request",
                    message = tostring(message),
                },
            }
            report.completed = report.completed + 1
            report.failed = report.failed + 1
            run_next(index + 1)
        end

        if type(name) ~= "string" or name:match("^%s*$") then
            record_failure("Each call requires a non-empty tool name")
            return
        end

        if name == "task_manager" then
            record_failure(
                "Nested TaskManager calls are not supported",
                {
                    category = "invalid_request",
                    message = "Nested TaskManager calls are not supported",
                }
            )
            return
        end

        if type(tool_arguments) ~= "table" then
            record_failure(
                "Tool arguments must be an object",
                {
                    category = "invalid_request",
                    message = "Tool arguments must be an object",
                }
            )
            return
        end

        local completed = false
        local function on_tool_complete(result, err)
            if completed then
                return
            end
            completed = true

            local item = {
                index = index,
                name = name,
                status = err and "failed" or "success",
                arguments = tool_arguments,
            }

            if err then
                if type(err) == "table" then
                    item.error = err
                else
                    item.error = {
                        category = "tool_error",
                        message = tostring(err),
                    }
                end
                report.failed = report.failed + 1
            else
                item.result = result
                report.succeeded = report.succeeded + 1
            end

            report.results[#report.results + 1] = item
            report.completed = report.completed + 1

            -- A failed tool is recorded as data; the next call still runs.
            run_next(index + 1)
        end

        local ok, immediate_error = pcall(
            execute,
            name,
            tool_arguments,
            on_tool_complete
        )

        if not ok then
            on_tool_complete(nil, {
                category = "tool_exception",
                message = tostring(immediate_error),
            })
        end
    end

    run_next(1)
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "task_manager",
        description =
            "Execute an ordered batch of up to 8 existing tools in the Lua Middleware. "
            .. "Provide each tool name and its complete arguments up front. Calls run "
            .. "sequentially; each returns a success or failure status and its result "
            .. "or structured error, and later calls still run after a failure. This "
            .. "first version does not pass one call's result into later call arguments. "
            .. "Use it when several independent tool calls belong to the current request.",
        parameters = {
            type = "object",
            properties = {
                calls = {
                    type = "array",
                    minItems = 1,
                    maxItems = 8,
                    description = "Ordered tool calls to execute.",
                    items = {
                        type = "object",
                        properties = {
                            name = {
                                type = "string",
                                description = "Exact name of an existing Alice tool.",
                            },
                            arguments = {
                                type = "object",
                                description = "Complete arguments for that tool.",
                            },
                        },
                        required = {"name", "arguments"},
                    },
                },
            },
            required = {"calls"},
        },
    },
}

return M
