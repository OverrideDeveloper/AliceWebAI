-- Alice Web AI
-- Web search tool adapter for the standalone lua-web-search module.
-- Lua 5.1 / Luvit compatible.

local WebSearchEngine = require("./lua-web-search/web_search_engine")
local DuckDuckGo = require("./lua-web-search/providers/duckduckgo")

local M = {}

M.config = {
    max_results = 5,
    provider = "auto",
}

local engine = WebSearchEngine.new({
    max_results = M.config.max_results,
})

engine:add_provider(DuckDuckGo.new({
    user_agent = "AliceWebAI/1.0 web-search",
}))

local function map_provider_error(retrieval)
    if retrieval.status == "access_challenge" then
        return {
            category = "provider_challenge",
            provider = retrieval.provider,
            message = retrieval.message
                or (retrieval.provider .. " returned an access challenge"),
        }
    end

    if retrieval.status == "network_error" then
        return {
            category = "provider_unavailable",
            provider = retrieval.provider,
            message = retrieval.message
                or (retrieval.provider .. " network request failed"),
        }
    end

    if retrieval.status == "http_error" then
        return {
            category = "provider_unavailable",
            provider = retrieval.provider,
            message = retrieval.message
                or (retrieval.provider .. " returned an HTTP error"),
        }
    end

    if retrieval.status == "zero_results" then
        return nil
    end

    if retrieval.status ~= "success" then
        return {
            category = "provider_unavailable",
            provider = retrieval.provider,
            message = retrieval.message
                or (retrieval.provider .. " search failed"),
        }
    end

    return nil
end

function M.search(arguments, callback)
    arguments = arguments or {}

    local requested_provider =
        tostring(arguments.provider or M.config.provider):lower()

    if requested_provider ~= "auto"
        and requested_provider ~= "duckduckgo" then
        callback(nil, {
            category = "provider_unavailable",
            message = "Unsupported web search provider: "
                .. requested_provider,
        })
        return
    end

    local count =
        tonumber(arguments.count or M.config.max_results)
        or M.config.max_results

    count = math.floor(count)

    if count < 1 then
        count = 1
    elseif count > 10 then
        count = 10
    end

    engine.max_results = count

    engine:search(
        tostring(arguments.query or ""),
        function(result)
            if not result then
                callback(nil, {
                    category = "provider_unavailable",
                    message = "Web search engine returned no result.",
                })
                return
            end

            for _, retrieval in ipairs(result.retrieval or {}) do
                local provider_error = map_provider_error(retrieval)
                if provider_error then
                    callback(nil, provider_error)
                    return
                end
            end

            callback(result, nil)
        end
    )
end

M._classify_response = DuckDuckGo._classify_response
M._parse_results = function(body, max_results, provider_name)
    if provider_name == "DuckDuckGo" then
        return DuckDuckGo._parse_results(body, max_results)
    end

    return {}
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "web_search",
        description =
            "Search the public Internet and return attributed search results. "
            .. "Use this for current information, research, fact checking, "
            .. "or when the user's request requires information beyond the "
            .. "model's local knowledge. Treat results as retrieved evidence, "
            .. "not automatically verified facts. Do not invent URLs or sources.",
        parameters = {
            type = "object",
            properties = {
                query = {
                    type = "string",
                    description = "The web search query."
                },
                count = {
                    type = "integer",
                    description = "Number of results from 1 to 10. Defaults to 5."
                },
                provider = {
                    type = "string",
                    enum = {"auto", "duckduckgo"},
                    description = "Search provider. Defaults to auto."
                }
            },
            required = {"query"}
        }
    }
}

return M
