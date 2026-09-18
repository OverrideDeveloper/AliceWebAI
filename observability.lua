-- Alice Web AI
-- Structured request/tool observability and error classification.
-- Lua 5.1 compatible.

local json = require("json")

local M = {}
local sequence = 0
local counters = {}

local function safe_string(value)
    return tostring(value or "")
end

function M.new_request_id()
    sequence = sequence + 1
    return string.format(
        "%x-%x-%x",
        os.time(),
        math.floor((os.clock() % 1) * 1000000),
        sequence
    )
end

function M.classify_error(message)
    local text = safe_string(message):lower()

    if text:match("timed out") or text:match("timeout") then
        return "timeout"
    end

    if text:match("http %d") then
        return "http_error"
    end

    if text:match("decode") or text:match("json") then
        return "protocol_error"
    end

    if text:match("unknown tool") or text:match("malformed tool") then
        return "tool_error"
    end

    if text:match("empty response") or text:match("no response") then
        return "empty_response"
    end

    if text:match("permission") or text:match("not permitted") then
        return "authorization_error"
    end

    return "internal_error"
end

function M.new_context(fields)
    fields = fields or {}

    local context = {
        request_id = fields.request_id or M.new_request_id(),
        user_id = fields.user_id,
        provider = fields.provider,
        tool_round = fields.tool_round,
        tool_name = fields.tool_name,
        started_at = os.time(),
    }

    return context
end

function M.log(event, context, fields)
    local record = {
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        event = safe_string(event),
        request_id = context and context.request_id or nil,
    }

    if context then
        record.user_id = context.user_id
        record.provider = context.provider
        record.tool_round = context.tool_round
        record.tool_name = context.tool_name
    end

    for key, value in pairs(fields or {}) do
        record[key] = value
    end

    local encoded = json.encode(record)

    if encoded then
        print("[ALICE] " .. encoded)
    else
        print("[ALICE] event=" .. safe_string(event))
    end
end

function M.error(event, context, message, fields)
    local category = M.classify_error(message)

    counters[category] = (counters[category] or 0) + 1

    local data = fields or {}
    data.error_category = category
    data.error_message = safe_string(message)

    M.log(event, context, data)

    return {
        category = category,
        message = safe_string(message),
    }
end

function M.increment(name)
    counters[name] = (counters[name] or 0) + 1
end

function M.get_counters()
    local result = {}

    for key, value in pairs(counters) do
        result[key] = value
    end

    return result
end

return M
