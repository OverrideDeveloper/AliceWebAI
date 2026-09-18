-- Alice Web AI
-- Model response post-processing and epistemic guardrails.
-- Lua 5.1 compatible.

local M = {}

function M.inspect(response, metadata)
    metadata = metadata or {}

    local text = tostring(response or "")

    return {
        response = text,
        has_model_certainty_marker =
            text:match("Certainty Level%s*:") ~= nil,
        web_evidence_used =
            metadata.web_evidence_used == true,
        evidence_status =
            metadata.web_evidence_used
                and "retrieved"
                or "model_only",
    }
end

function M.decorate(response, metadata)
    local inspected = M.inspect(response, metadata)

    local suffix = {
        "",
        "--- ALICE EVIDENCE STATUS ---",
        "Evidence status: " .. inspected.evidence_status,
    }

    if inspected.web_evidence_used then
        suffix[#suffix + 1] =
            "Web search results were retrieved by Alice; claims should be grounded in the supplied results."
    else
        suffix[#suffix + 1] =
            "No web evidence was retrieved for this response."
    end

    return inspected.response .. "\n\n" .. table.concat(suffix, "\n")
end

return M
