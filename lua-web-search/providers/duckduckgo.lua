local https = require("https")

local DuckDuckGo = {}
DuckDuckGo.__index = DuckDuckGo

local function url_encode(value)
    return (value:gsub("([^%w%-_%.~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function html_decode(value)
    value = value:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
    value = value:gsub("&quot;", '"'):gsub("&#39;", "'")
    return value
end

local function strip_tags(value)
    value = html_decode(value:gsub("<[^>]+>", " "))
    return (value:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
end

local function classify(body, status)
    if not status or status ~= 200 then return "http_error" end
    local lower = body:lower()
    if lower:find("unfortunately, bots use duckduckgo too", 1, true)
        or lower:find("confirm this search was made by a human", 1, true)
        or lower:find("anomaly-modal__title", 1, true) then
        return "access_challenge"
    end
    return "search_page"
end

local function parse_results(body, max_results)
    local results = {}

    for block in body:gmatch('<div[^>]-class="result[^"]*"[^>]*>(.-)</div>%s*</div>') do
        local href, title = block:match(
            '<a[^>]-class="[^"]*result__a[^"]*"[^>]-href="([^"]+)"[^>]*>(.-)</a>'
        )
        if href and title then
            local snippet = block:match(
                '<a[^>]-class="[^"]*result__snippet[^"]*"[^>]*>(.-)</a>'
            ) or block:match(
                '<div[^>]-class="[^"]*result__snippet[^"]*"[^>]*>(.-)</div>'
            )
            results[#results + 1] = {
                title = strip_tags(title),
                url = html_decode(href),
                snippet = strip_tags(snippet or ""),
            }
            if #results >= max_results then break end
        end
    end

    if #results == 0 then
        for href, title in body:gmatch(
            '<a[^>]-class="[^"]*result__a[^"]*"[^>]-href="([^"]+)"[^>]*>([^<]+)</a>'
        ) do
            results[#results + 1] = {
                title = strip_tags(title),
                url = html_decode(href),
                snippet = "",
            }
            if #results >= max_results then break end
        end
    end

    return results
end

function DuckDuckGo.new(options)
    options = options or {}
    return setmetatable({
        name = "duckduckgo",
        host = options.host or "html.duckduckgo.com",
        path = options.path or "/html/",
        user_agent = options.user_agent or "lua-web-search/0.1",
    }, DuckDuckGo)
end

function DuckDuckGo:search(query, max_results, callback)
    local chunks = {}
    local request = https.request({
        host = self.host,
        path = self.path .. "?q=" .. url_encode(query),
        method = "GET",
        headers = {
            ["User-Agent"] = self.user_agent,
            ["Accept"] = "text/html,application/xhtml+xml",
            ["Connection"] = "close",
        },
    }, function(response)
        response:on("data", function(chunk) chunks[#chunks + 1] = chunk end)
        response:on("end", function()
            local body = table.concat(chunks)
            local status_code = tonumber(response.statusCode or response.code)
            local status = classify(body, status_code)

            if status == "access_challenge" then
                callback({
                    status = status,
                    results = {},
                    message = "DuckDuckGo returned an automated-access challenge.",
                })
                return
            end

            if status == "http_error" then
                callback({
                    status = status,
                    results = {},
                    message = "DuckDuckGo returned HTTP status " .. tostring(status_code),
                })
                return
            end

            local results = parse_results(body, max_results)
            callback({
                status = #results > 0 and "success" or "zero_results",
                results = results,
                message = #results > 0 and nil
                    or "DuckDuckGo returned a search page but no results were parsed.",
            })
        end)
    end)

    request:on("error", function(err)
        callback({ status = "network_error", results = {}, message = tostring(err) })
    end)
    request:done()
end

DuckDuckGo._classify_response = classify
DuckDuckGo._parse_results = parse_results

return DuckDuckGo
