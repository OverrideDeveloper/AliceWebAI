-- Alice Web AI
-- Model response post-processing and epistemic guardrails.
-- Lua 5.1 compatible.

local Evidence = require("./evidence")

local M = {}

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
    local inspected = M.inspect(response, metadata)
    local suffix = {
        "",
        "--- ALICE EVIDENCE STATUS ---",
        "Evidence status: " .. inspected.evidence_status,
        "Claim provenance: " .. tostring(#inspected.claims) .. " candidate claims classified.",
    }

    if inspected.has_model_certainty_marker then
        suffix[#suffix + 1] = "Legacy certainty marker detected; provenance is authoritative instead."
    end

    if inspected.provenance_theater then
        suffix[#suffix + 1] = "WARNING: response claims external verification without a matching evidence event."
    end

    if inspected.freshness_gap then
        suffix[#suffix + 1] = "WARNING: response uses freshness-sensitive language without retrieved current evidence."
    end

    if inspected.web_evidence_used then
        if #inspected.web_urls > 0 then
            suffix[#suffix + 1] = "Retrieved sources:"
            for i, url in ipairs(inspected.web_urls) do
                suffix[#suffix + 1] = string.format("%d. %s", i, url)
            end
        else
            suffix[#suffix + 1] = "WARNING: web evidence event occurred but supplied source URLs were unavailable."
        end
    else
        suffix[#suffix + 1] = "No web evidence was retrieved for this response."
    end

    return inspected.response .. "\n\n" .. table.concat(suffix, "\n")
end

return M
