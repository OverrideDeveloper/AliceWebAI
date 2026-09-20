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

M.config = {
    host = "html.duckduckgo.com",
    path = "/html/",
    timeout = 20,
    max_results = 5,
    region = "us-en",
    debug = true,
    debug_body_limit = 4000,
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

local function parse_results(body, max_results)
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
                engine = "DuckDuckGo",
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

local function request(query, callback)
    local path =
        M.config.path
        .. "?q="
        .. url_encode(query)
        .. "&kl="
        .. url_encode(M.config.region)

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
                    host = M.config.host,
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

    request(query, function(response, err)
        if err then
            callback(nil, err)
            return
        end

        local body = response.body or ""
        local status = tonumber(response.status or 0)
        local headers = response.headers or {}

        if M.config.debug then
            local content_type = headers["content-type"] or headers["Content-Type"] or ""
            print("[DuckDuckGo raw response]")
            print("  query: " .. query)
            print("  http_status: " .. tostring(status))
            print("  content_type: " .. tostring(content_type))
            print("  body_bytes: " .. tostring(#body))
            print("  body_preview_bytes: " .. tostring(math.min(#body, M.config.debug_body_limit)))
            print("  body_preview_begin")
            print(body:sub(1, M.config.debug_body_limit))
            print("  body_preview_end")
            print("[End DuckDuckGo raw response]")
        end

        local results =
            parse_results(body, count)

        print("[DuckDuckGo payload]")
        print("  query: " .. query)
        print("  result_count: " .. tostring(#results))

        for _, result in ipairs(results) do
            print(string.format(
                "  [%d] %s | %s | %s",
                result.rank,
                result.title,
                result.url,
                result.snippet
            ))
        end

        print("[End DuckDuckGo payload]")

        if M.config.debug then
            print("[DuckDuckGo parser diagnosis]")
            print("  parser_result_count: " .. tostring(#results))
            print("  requested_result_count: " .. tostring(count))
            print("  parser_status: " .. (#results > 0 and "results_found" or "no_results_parsed"))
            print("[End DuckDuckGo parser diagnosis]")
        end

        callback(
            {
                query = query,
                engine = "DuckDuckGo",
                results = results,
                evidence = Evidence.encode(
                    (function()
                        local items = {}
                        for _, result in ipairs(results) do
                            items[#items + 1] =
                                Evidence.web_result(result)
                        end
                        return items
                    end)()
                ),
                rendered =
                    Evidence.render_web_results(results),
            },
            nil
        )
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
