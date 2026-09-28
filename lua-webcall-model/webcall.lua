-- lua-webcall-model
-- A small, standalone HTTP/HTTPS request abstraction for Lua/Luvit.

local http = require("http")
local https = require("https")

local M = {}

local function parse_url(value)
    assert(type(value) == "string", "url must be a string")

    local scheme, authority, rest = value:match("^([%a][%w+.-]*)://([^/%?#]+)(.*)$")
    assert(scheme, "url must include an http:// or https:// scheme")

    scheme = scheme:lower()
    assert(scheme == "http" or scheme == "https",
        "unsupported URL scheme: " .. scheme)

    local host, port = authority:match("^([^:]+):(%d+)$")
    if not host then
        host = authority
    end

    assert(host and host ~= "", "url must include a host")

    rest = rest or ""
    local path = rest:match("^([^#]*)") or ""
    if path == "" then
        path = "/"
    elseif path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end

    local default_port = scheme == "https" and 443 or 80

    return {
        scheme = scheme,
        host = host,
        port = tonumber(port) or default_port,
        path = path,
    }
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end

local function finish_once(callback)
    local finished = false

    return function(response, err)
        if finished then
            return
        end

        finished = true
        callback(response, err)
    end
end

local function request(options, callback)
    if type(options) ~= "table" then
        error("request options must be a table")
    end
    if type(options.url) ~= "string" then
        error("request options require a url")
    end
    if type(callback) ~= "function" then
        error("request callback must be a function")
    end

    local done = finish_once(callback)
    local ok, parsed = pcall(parse_url, options.url)

    if not ok then
        done(nil, parsed)
        return
    end

    local headers = copy_table(options.headers)
    local body = options.body

    if body ~= nil and type(body) ~= "string" then
        done(nil, "request body must be a string")
        return
    end

    if body ~= nil then
        if headers["Content-Length"] == nil and headers["content-length"] == nil then
            headers["Content-Length"] = #body
        end
    end

    if headers["Connection"] == nil and headers["connection"] == nil then
        headers["Connection"] = "close"
    end

    local method = options.method or "GET"
    if type(method) ~= "string" then
        done(nil, "request method must be a string")
        return
    end
    method = method:upper()
    local request_options = {
        host = parsed.host,
        port = options.port or parsed.port,
        path = parsed.path,
        method = method,
        headers = headers,
    }

    if parsed.scheme == "https" then
        -- Luvit's TLS binding uses OpenSSL method names here. "TLS_client"
        -- asks OpenSSL for the version-flexible client method; it is not a
        -- TLS version selector such as "TLSv1_2".
        request_options.secureProtocol = options.secureProtocol or "TLS_client"

        -- Luvit passes hostname into its TLS layer for client SNI.
        -- Keep it tied to the URL host by default, while allowing callers
        -- to override it when the connection host and certificate name differ.
        request_options.hostname = options.servername or parsed.host

        local tls_options = {
            "ca",
            "cert",
            "key",
            "pfx",
            "passphrase",
            "ciphers",
            "rejectUnauthorized",
            "secureProtocol",
            "secureOptions",
        }

        for _, key in ipairs(tls_options) do
            if options[key] ~= nil then
                request_options[key] = options[key]
            end
        end
    end

    local transport = parsed.scheme == "https" and https or http

    local request_ok, req = pcall(transport.request, request_options, function(res)
        local chunks = {}

        res:on("data", function(chunk)
            chunks[#chunks + 1] = chunk
        end)

        res:on("end", function()
            local response = {
                status = res.statusCode,
                headers = res.headers or {},
                body = table.concat(chunks),
                url = options.url,
                method = method,
            }

            if res.statusCode and res.statusCode >= 200 and res.statusCode < 300 then
                done(response, nil)
            else
                done(response, string.format("HTTP request failed with status %s",
                    tostring(res.statusCode)))
            end
        end)

        res:on("error", function(err)
            done(nil, err)
        end)
    end)

    if not request_ok then
        done(nil, req)
        return
    end

    req:on("error", function(err)
        done(nil, err)
    end)

    if options.timeout then
        req:setTimeout(options.timeout, function()
            done(nil, "request timed out after " .. tostring(options.timeout) .. "ms")
            req:destroy()
        end)
    end

    if body ~= nil then
        req:write(body)
    end

    req:done()
end

function M.request(options, callback)
    return request(options, callback)
end

function M.get(url, options, callback)
    if type(options) == "function" then
        callback = options
        options = {}
    end

    options = copy_table(options)
    options.url = url
    options.method = "GET"

    return request(options, callback)
end

function M.post(url, body, options, callback)
    if type(options) == "function" then
        callback = options
        options = {}
    end

    options = copy_table(options)
    options.url = url
    options.method = "POST"
    options.body = body

    return request(options, callback)
end

-- Exposed for small consumers/tests that need to inspect URL normalization.
M.parse_url = parse_url

return M
