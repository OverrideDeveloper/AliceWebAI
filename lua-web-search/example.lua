local WebSearchEngine = require("./lua-web-search/web_search_engine")
local DuckDuckGo = require("./lua-web-search/providers/duckduckgo")

local search = WebSearchEngine.new({ max_results = 5 })
search:add_provider(DuckDuckGo.new())

search:search("famous historical events on September 20", function(result)
    print("status: " .. result.status)
    print("query: " .. result.query)

    for _, item in ipairs(result.results) do
        print(string.format("- %s | %s", item.title, item.url))
    end

    for _, retrieval in ipairs(result.retrieval) do
        print(string.format(
            "provider=%s status=%s results=%d",
            retrieval.provider, retrieval.status, retrieval.result_count
        ))
    end
end)
