-- Alice Web AI
-- Model response post-processing and epistemic guardrails.
-- Lua 5.1 compatible.

local Evidence = require("./evidence")

local M = {}

local TOOL_ARGUMENT_MAX_DEPTH = 4
local TOOL_ARGUMENT_MAX_ITEMS = 32

local function quote_tool_argument_string(value)
    value = tostring(value)
    value = value:gsub("\\", "\\\\")
    value = value:gsub("\"", "\\\"")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\t", "\\t")
    return "\"" .. value .. "\""
end

local function is_array_table(value)
    if type(value) ~= "table" then
        return false, 0
    end

    local count = 0

    for key, _ in pairs(value) do
        if type(key) ~= "number"
           or key < 1
           or key % 1 ~= 0 then
            return false, 0
        end

        count = count + 1
    end

    for index = 1, count do
        if value[index] == nil then
            return false, 0
        end
    end

    return true, count
end

local function sorted_object_keys(value)
    local keys = {}

    for key, _ in pairs(value) do
        keys[#keys + 1] = key
    end

    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    return keys
end

local function format_tool_argument(value, depth)
    if value == nil then
        return "null"
    end

    local value_type = type(value)

    if value_type == "string" then
        return quote_tool_argument_string(value)
    end

    if value_type == "number"
       or value_type == "boolean" then
        return tostring(value)
    end

    if value_type ~= "table" then
        return "<" .. value_type .. ">"
    end

    if depth >= TOOL_ARGUMENT_MAX_DEPTH then
        return "<max depth>"
    end

    local is_array, count = is_array_table(value)

    if is_array then
        if count == 0 then
            return "[]"
        end

        local parts = {}
        local limit = math.min(count, TOOL_ARGUMENT_MAX_ITEMS)

        for index = 1, limit do
            parts[#parts + 1] =
                format_tool_argument(
                    value[index],
                    depth + 1
                )
        end

        if count > limit then
            parts[#parts + 1] = "<truncated>"
        end

        return "[" .. table.concat(parts, ", ") .. "]"
    end

    local parts = {}
    local keys = sorted_object_keys(value)
    local limit = math.min(#keys, TOOL_ARGUMENT_MAX_ITEMS)

    for index = 1, limit do
        local key = keys[index]
        parts[#parts + 1] =
            tostring(key)
            .. ": "
            .. format_tool_argument(
                value[key],
                depth + 1
            )
    end

    if #keys > limit then
        parts[#parts + 1] = "<truncated>"
    end

    if #parts == 0 then
        return "{}"
    end

    return "{" .. table.concat(parts, ", ") .. "}"
end

local function split_claims(text)
    local claims = {}
    for sentence in tostring(text or ""):gmatch("[^.!?]+[.!?]?") do
        sentence = sentence:match("^%s*(.-)%s*$") or ""
        if sentence ~= "" then
            claims[#claims + 1] = sentence
        end
    end
    return claims
end

local function contains_url(text, urls)
    for _, url in ipairs(urls or {}) do
        if url ~= "" and tostring(text):find(url, 1, true) then
            return true, url
        end
    end
    return false, nil
end

local function looks_like_provenance_claim(text)
    local lower = tostring(text or ""):lower()
    return lower:match("i%s+searched")
        or lower:match("i%s+checked")
        or lower:match("i%s+looked%s+up")
        or lower:match("i%s+verified")
        or lower:match("according%s+to%s+my%s+search")
end

local function needs_freshness(text)
    local lower = tostring(text or ""):lower()
    return lower:match("%btoday%f[%W]")
        or lower:match("%bnow%f[%W]")
        or lower:match("%blatest%f[%W]")
        or lower:match("%bcurrent%f[%W]")
        or lower:match("%bas%s+of%s+%d%d%d%d%f[%W]")
end

function M.inspect(response, metadata)
    metadata = metadata or {}
    local text = tostring(response or "")
    local urls = metadata.web_urls or {}
    local web_used = metadata.web_evidence_used == true
    local claims = {}
    local provenance_theater = false
    local freshness_gap = false

    for _, sentence in ipairs(split_claims(text)) do
        local linked, url = contains_url(sentence, urls)
        local status = linked and Evidence.STATUS.RETRIEVED or Evidence.STATUS.CONSTRUCTED
        claims[#claims + 1] = Evidence.claim(
            sentence,
            status,
            linked and {url} or {},
            {role = linked and "retrieved_claim" or "candidate_claim"}
        )
        if looks_like_provenance_claim(sentence) and not web_used then
            provenance_theater = true
        end
    end

    if needs_freshness(text) and not web_used then
        freshness_gap = true
    end

    return {
        response = text,
        has_model_certainty_marker = text:match("Certainty Level%s*:") ~= nil,
        web_evidence_used = web_used,
        web_urls = urls,
        claims = claims,
        provenance_theater = provenance_theater,
        freshness_gap = freshness_gap,
        evidence_status = web_used and "retrieved" or "model_only",
    }
end

function M.decorate(response, metadata)
    metadata = metadata or {}

    local inspected = M.inspect(response, metadata)
    local decorated = inspected.response
    local tool_calls = metadata.tool_calls or {}

    if #tool_calls > 0 then
        local lines = {
            "",
            "--- Tool execution ---",
            "The model ran the following tool(s); this reply may contain results from them.",
        }

        for _, tool_call in ipairs(tool_calls) do
            local name = tool_call.tool_name or "unknown"
            lines[#lines + 1] = string.format(
                "- %s",
                name
            )

            if type(tool_call.arguments) == "table" then
                for _, key in ipairs(sorted_object_keys(tool_call.arguments)) do
                    lines[#lines + 1] = string.format(
                        "  %s: %s",
                        tostring(key),
                        format_tool_argument(
                            tool_call.arguments[key],
                            1
                        )
                    )
                end
            end
        end

        decorated = decorated .. "\n" .. table.concat(lines, "\n")
    end

    -- Keep the full inspection result available to callers for future
    -- operator/diagnostic output, but do not leak internal epistemic
    -- diagnostics into the human-facing response.
    return decorated
end

return M
