-- Alice Web AI
-- Evidence and provenance primitives.
-- Lua 5.1 compatible.

local json = require("json")

local M = {}

M.STATUS = {
    OBSERVED = "observed",
    RETRIEVED = "retrieved",
    INFERRED = "inferred",
    ASSERTED = "asserted",
    VERIFIED = "verified",
    UNAVAILABLE = "unavailable",
}

function M.new(source, status, content, metadata)
    return {
        source = source or "unknown",
        status = status or M.STATUS.ASSERTED,
        content = content or "",
        metadata = metadata or {},
        timestamp = os.time(),
    }
end

function M.web_result(result)
    return M.new(
        "web_search",
        M.STATUS.RETRIEVED,
        result.snippet or result.title or "",
        {
            title = result.title,
            url = result.url,
            rank = result.rank,
            engine = result.engine,
        }
    )
end

function M.render_web_results(results)
    local output = {
        "WEB EVIDENCE - RETRIEVED RESULTS",
        "These are search results, not independently verified facts.",
        "Use the supplied URLs for provenance. Do not invent sources.",
    }

    for i, result in ipairs(results or {}) do
        output[#output + 1] = string.format(
            "%d. %s",
            i,
            tostring(result.title or "")
        )

        output[#output + 1] = "   URL: " .. tostring(result.url or "")
        output[#output + 1] = "   Snippet: " .. tostring(result.snippet or "")
    end

    return table.concat(output, "\n")
end

function M.encode(items)
    return json.encode(items or {})
end

return M
