-- Alice Web AI
-- Internet search tool using DuckDuckGo's non-JavaScript HTML search.
-- Lua 5.1 / Luvit compatible.
--
-- The search engine is a replaceable provider boundary. The default
-- provider is DuckDuckGo HTML so local development works without an API key.

local https = require("https")
local json = require("json")
local Evidence = require("./evidence")

local M = {}

local PROVIDERS = {
    {
        name = "DuckDuckGo",
        host = "html.duckduckgo.com",
        path = "/html/",
        region_parameter = "kl",
    },
    {
        name = "Mojeek",
        host = "www.mojeek.com",
        path = "/search",
        region_parameter = nil,
    },
}

M.config = {
    host = "html.duckduckgo.com",
    path = "/html/",
    timeout = 20,
    max_results = 5,
    region = "us-en",
    debug = true,
    debug_body_limit = 4000,
    max_provider_attempts = 2,
    provider = "auto",
}

local function html_decode(value)
    value = tostring(value or "")

    local entities = {
        ["&amp;"] = "&",
        ["&quot;"] = '"',
        ["&#39;"] = "'",
        ["&lt;"] = "<",
        ["&gt;"] = ">",
    }

    for entity, replacement in pairs(entities) do
        value = value:gsub(entity, replacement)
    end

    return value
end

local function url_encode(value)
    value = tostring(value or "")

    return (value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function html_to_text(value)
    value = tostring(value or "")
    value = value:gsub("<[^>]+>", " ")
    value = html_decode(value)
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function decode_url(value)
    value = tostring(value or "")

    value = value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)

    return value
end

local function normalize_result_url(href)
    href = html_decode(href)

    local encoded =
        href:match("[?&]uddg=([^&]+)")

    if encoded then
        return decode_url(encoded)
    end

    if href:match("^//") then
        return "https:" .. href
    end

    return href
end

local function classify_response(provider_name, body)
    local lower = tostring(body or ""):lower()

    if provider_name == "DuckDuckGo"
        and (
            lower:find("anomaly-modal__title", 1, true)
            or lower:find("unfortunately, bots use duckduckgo too", 1, true)
            or lower:find("confirm this search was made by a human", 1, true)
        ) then
        return "access_challenge"
    end

    return "search_page"
end

local function make_result(provider_name, rank, href, title, snippet)
    return {
        rank = rank,
        title = html_to_text(title),
        url = normalize_result_url(href),
        snippet = html_to_text(snippet or ""),
        engine = provider_name,
        provider = provider_name,
    }
end

local function parse_mojeek(body, max_results)
    local results = {}

    for block in body:gmatch(
        '<li[^>]-class="[^"]*result[^"]*"[^>]*>(.-)</li>'
    ) do
        local href, title =
            block:match(
                '<h2[^>]*>.-<a[^>]-href="([^"]+)"[^>]*>(.-)</a>.-</h2>'
            )

        if not href then
            href, title =
                block:match(
                    '<a[^>]-class="ob"[^>]-href="([^"]+)"[^>]*>(.-)</a>'
                )
        end

        if href and title then
            local snippet =
                block:match(
                    '<p[^>]-class="[^"]*s[^"]*"[^>]*>(.-)</p>'
                )

            results[#results + 1] =
                make_result("Mojeek", #results + 1, href, title, snippet)

            if #results >= max_results then
                break
            end
        end
    end

    if #results == 0 then
        for href, title in body:gmatch(
            '<a[^>]-class="ob"[^>]-href="([^"]+)"[^>]*>(.-)</a>'
        ) do
            results[#results + 1] =
                make_result("Mojeek", #results + 1, href, title, "")

            if #results >= max_results then
                break
            end
        end
    end

    return results
end

local function parse_results(body, max_results, provider_name)
    if provider_name == "Mojeek" then
        return parse_mojeek(body, max_results)
    end

    local results = {}

    for block in body:gmatch('<div[^>]-class="result[^"]*"[^>]*>(.-)</div>%s*</div>') do
        local href, title =
            block:match('<a[^>]-class="[^"]*result__a[^"]*"[^>]-href="([^"]+)"[^>]*>(.-)</a>')

        if href and title then
            local snippet =
                block:match('<a[^>]-class="[^"]*result__snippet[^"]*"[^>]*>(.-)</a>')

            results[#results + 1] = {
                rank = #results + 1,
                title = html_to_text(title),
                url = normalize_result_url(href),
                snippet = html_to_text(snippet or ""),
                engine = provider_name or "DuckDuckGo",
                provider = provider_name or "DuckDuckGo",
            }

            if #results >= max_results then
                break
            end
        end
    end

    -- Some DDG layouts do not wrap results in the same outer div.
    -- Fall back to scanning result links directly.
    if #results == 0 then
        for href, title in body:gmatch(
            '<a[^>]-class="[^"]*result__a[^"]*"[^>]-href="([^"]+)"[^>]*>(.-)</a>'
        ) do
            results[#results + 1] = {
                rank = #results + 1,
                title = html_to_text(title),
                url = normalize_result_url(href),
                snippet = "",
                engine = "DuckDuckGo",
            }

            if #results >= max_results then
                break
            end
        end
    end

    return results
end

local function request(provider, query, callback)
    local path =
        provider.path
        .. "?q="
        .. url_encode(query)

    if provider.region_parameter then
        path = path
            .. "&"
            .. provider.region_parameter
            .. "="
            .. url_encode(M.config.region)
    end

    local response_data = {}
    local response_headers = {}
    local completed = false

    local function finish(result, err)
        if completed then
            return
        end

        completed = true
        callback(result, err)
    end

    local ok, req_or_error =
        pcall(function()
            return https.request(
                {
                    host = provider.host,
                    port = 443,
                    path = path,
                    method = "GET",
                    headers = {
                        ["User-Agent"] =
                            "AliceWebAI/1.0 web-search",
                        ["Accept"] =
                            "text/html,application/xhtml+xml",
                        ["Connection"] = "close",
                    },
                },
                function(res)
                    local status =
                        tonumber(res.statusCode or 0)

                    response_headers = res.headers or {}

                    res:on("data", function(chunk)
                        response_data[#response_data + 1] = chunk
                    end)

                    res:on("end", function()
                        local body =
                            table.concat(response_data)

                        if status < 200 or status >= 300 then
                            finish(
                                nil,
                                string.format(
                                    "Web search HTTP %d: %s",
                                    status,
                                    body:sub(1, 500)
                                )
                            )
                            return
                        end

                        if body == "" then
                            finish(
                                nil,
                                "Web search returned an empty response"
                            )
                            return
                        end

                        finish(
                            {
                                body = body,
                                status = status,
                                headers = response_headers,
                            },
                            nil
                        )
                    end)
                end
            )
        end)

    if not ok then
        finish(
            nil,
            "Unable to create web search request: "
                .. tostring(req_or_error)
        )
        return
    end

    local req = req_or_error

    req:on("error", function(err)
        finish(
            nil,
            "Web search request error: "
                .. tostring(err)
        )
    end)

    req:setTimeout(
        M.config.timeout * 1000,
        function()
            finish(
                nil,
                "Web search timed out after "
                    .. tostring(M.config.timeout)
                    .. " seconds"
            )
            req:destroy()
        end
    )

    req:done()
end

local function build_search_result(provider_name, query, results)
    local items = {}
    for _, result in ipairs(results or {}) do
        items[#items + 1] = Evidence.web_result(result)
    end

    return {
        query = query,
        engine = provider_name,
        provider = provider_name,
        results = results,
        evidence = Evidence.encode(items),
        rendered = Evidence.render_web_results(results),
    }
end

local function search_provider(provider, query, count, callback)
    request(provider, query, function(response, err)
        if err then
            callback(nil, err)
            return
        end

        local body = response.body or ""
        local response_type = classify_response(provider.name, body)

        if M.config.debug then
            local headers = response.headers or {}
            local content_type = headers["content-type"] or headers["Content-Type"] or ""
            print("[" .. provider.name .. " response]")
            print("  query: " .. query)
            print("  http_status: " .. tostring(response.status or 0))
            print("  content_type: " .. tostring(content_type))
            print("  body_bytes: " .. tostring(#body))
            print("  response_type: " .. response_type)
            print("  body_preview_begin")
            print(body:sub(1, M.config.debug_body_limit))
            print("  body_preview_end")
            print("[End " .. provider.name .. " response]")
        end

        if response_type ~= "search_page" then
            callback(nil, {
                category = response_type,
                provider = provider.name,
                message = provider.name .. " returned an access challenge",
            })
            return
        end

        local results = parse_results(body, count, provider.name)

        print("[" .. provider.name .. " payload]")
        print("  query: " .. query)
        print("  result_count: " .. tostring(#results))
        for _, result in ipairs(results) do
            print(string.format(
                "  [%d] %s | %s | %s",
                result.rank, result.title, result.url, result.snippet
            ))
        end
        print("[End " .. provider.name .. " payload]")

        callback(build_search_result(provider.name, query, results), nil)
    end)
end

function M.search(arguments, callback)
    arguments = arguments or {}

    local query =
        tostring(arguments.query or "")

    if query:match("^%s*$") then
        callback(
            nil,
            "Web search query is required"
        )
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

    local provider_index = 1

    local function try_provider(last_error)
        if provider_index > M.config.max_provider_attempts
            or provider_index > #PROVIDERS then
            callback(
                nil,
                {
                    category = last_error and last_error.category
                        or "provider_unavailable",
                    message = last_error and last_error.message
                        or "All configured web search providers failed",
                    provider = last_error and last_error.provider or nil,
                    attempts = provider_index - 1,
                }
            )
            return
        end

        local provider = PROVIDERS[provider_index]
        provider_index = provider_index + 1

        print(
            "[Web search provider attempt "
            .. tostring(provider_index - 1)
            .. "] "
            .. provider.name
        )

        search_provider(
            provider,
            query,
            count,
            function(result, err)
                if result then
                    callback(result, nil)
                    return
                end

                print(
                    "[Web search provider failed] "
                    .. provider.name
                    .. ": "
                    .. tostring(err and err.category or "unknown")
                )

                try_provider(err)
            end
        )
    end

    try_provider(nil)
    end)
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
                }
            },
            required = {"query"}
        }
    }
}

return M
