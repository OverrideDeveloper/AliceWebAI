local WebSearchEngine = {}
WebSearchEngine.__index = WebSearchEngine

local function normalize_result(result, provider)
    return {
        title = result.title or "",
        url = result.url or result.href or "",
        snippet = result.snippet or result.body or "",
        provider = result.provider or provider.name or "unknown",
    }
end

function WebSearchEngine.new(options)
    options = options or {}
    return setmetatable({
        providers = options.providers or {},
        max_results = options.max_results or 5,
    }, WebSearchEngine)
end

function WebSearchEngine:add_provider(provider)
    assert(type(provider) == "table", "provider must be a table")
    assert(type(provider.search) == "function", "provider.search must be a function")
    self.providers[#self.providers + 1] = provider
    return self
end

function WebSearchEngine:search(query, callback)
    assert(type(query) == "string" and query ~= "", "query must be a non-empty string")
    assert(type(callback) == "function", "callback must be a function")

    local retrieval, results = {}, {}
    local pending = #self.providers

    if pending == 0 then
        callback({ status = "no_providers", query = query, results = results, retrieval = retrieval })
        return
    end

    for _, provider in ipairs(self.providers) do
        local name = provider.name or "unknown"
        provider:search(query, self.max_results, function(outcome)
            outcome = outcome or { status = "provider_error", results = {} }

            retrieval[#retrieval + 1] = {
                provider = name,
                status = outcome.status or "unknown",
                result_count = #(outcome.results or {}),
                message = outcome.message,
            }

            for _, result in ipairs(outcome.results or {}) do
                if #results < self.max_results then
                    results[#results + 1] = normalize_result(result, provider)
                end
            end

            pending = pending - 1
            if pending == 0 then
                callback({
                    status = #results > 0 and "success" or "no_results",
                    query = query,
                    results = results,
                    retrieval = retrieval,
                })
            end
        end)
    end
end

return WebSearchEngine
