-- Alice Web AI
--
-- Copyright (C) 2026 Override Development
--
-- This file is part of Alice Web AI.
--
-- Alice Web AI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--------------------------------------

-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
-----------------------------------------------

-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- https://www.gnu.org/licenses/.

-- web_server.lua
-- Luvit HTTP server for Alice Web AI.
-- Lua 5.1 compatible.

local http = require("http")
local json = require("json")
local fs = require("fs")
local alice = require("./alice")
local auth = require("./local_identity")
local Observability = require("./observability")
local Policy = require("./policy")

local HOST = "127.0.0.1"
local PORT = 8080
local INDEX_FILE = "index.html"

local function send_json(res, status_code, data)
    local body = json.encode(data)

    if not body then
        body =
            '{"error":"Unable to encode server response"}'

        status_code = 500
    end

    res:writeHead(status_code, {
        ["Content-Type"] =
            "application/json; charset=utf-8",

        ["Content-Length"] =
            tostring(#body),

        ["Cache-Control"] =
            "no-cache",
    })

    res:finish(body)
end


local function send_text(res, status_code, text)
    text = tostring(text or "")

    res:writeHead(status_code, {
        ["Content-Type"] =
            "text/plain; charset=utf-8",

        ["Content-Length"] =
            tostring(#text),
    })

    res:finish(text)
end


local function read_request_body(req, callback)
    local chunks = {}

    req:on("data", function(chunk)
        chunks[#chunks + 1] = chunk
    end)

    req:on("end", function()
        callback(
            table.concat(chunks, "")
        )
    end)

    req:on("error", function(err)
        callback(nil, err)
    end)
end


local function sanitize_behaviors(value)
    if type(value) ~= "table" then
        return {}
    end

    -- Only accept the four known behavior names.
    -- Everything else is ignored.
    return {
        gaslighting =
            value.gaslighting == true,

        hallucination =
            value.hallucination == true,

        overconfidence =
            value.overconfidence == true,

        sycophancy =
            value.sycophancy == true,
    }
end


local function identity_response(identity)
    identity = identity or {}

    return {
        authenticated =
            identity.authenticated == true,

        anonymous =
            identity.anonymous == true,

        identity_name =
            identity.identity_name,

        user = {
            id =
                identity.user_id,

            name =
                identity.name,

            email =
                identity.email,

            provider =
                identity.provider,
        },
    }
end


-- Normalize identity information supplied by another frontend.
--
-- The Discord bot is a thin adapter. It does not authenticate through
-- this local identity provider. It supplies the Discord identity that
-- it already received from Discord.
--
-- Expected:
--
-- {
--     provider = "discord",
--     user_id = "123456789012345678",
--     name = "ExampleUser",
--     email = "optional",
--     authenticated = true,
--     anonymous = false
-- }
--
-- For now this is deliberately only identity propagation.
-- Real authentication/verification will eventually be supplied by
-- Cloudflare Access or the appropriate upstream identity layer.

local function identity_from_client(data)
    if type(data) ~= "table" then
        return nil
    end

    local provider =
        data.provider

    local user_id =
        data.user_id

    local name =
        data.name

    if type(provider) ~= "string" or
       provider == "" then
        return nil
    end

    if type(user_id) ~= "string" or
       user_id == "" then
        return nil
    end

    if type(name) ~= "string" or
       name == "" then
        return nil
    end

    local email = data.email

    if email ~= nil and
       type(email) ~= "string" then
        email = nil
    end

    local authenticated =
        data.authenticated == true

    local anonymous =
        data.anonymous == true

    return {
        user_id = user_id,
        name = name,
        email = email,
        provider = provider,
        authenticated = authenticated,
        anonymous = anonymous,
    }
end


local function handle_identity_get(req, res)
    local identity =
        auth.from_request(req)

    if not identity then
        identity =
            auth.get_default()
    end

    send_json(
        res,
        200,
        {
            identity =
                identity_response(identity)
        }
    )
end


local function handle_identity_select(req, res)
    read_request_body(
        req,
        function(body, body_error)

            if body_error then
                send_json(res, 400, {
                    error =
                        "Unable to read request: " ..
                        tostring(body_error)
                })

                return
            end

            local ok, data =
                pcall(
                    json.decode,
                    body
                )

            if not ok or
               type(data) ~= "table" then

                send_json(res, 400, {
                    error =
                        "Invalid JSON request"
                })

                return
            end

            local identity_name =
                data.identity

            if type(identity_name) ~= "string" or
               identity_name:match("^%s*$") then

                send_json(res, 400, {
                    error =
                        "Identity is required"
                })

                return
            end

            local identity =
                auth.get_identity(
                    identity_name
                )

            if not identity then
                send_json(res, 404, {
                    error =
                        "Unknown local identity"
                })

                return
            end

            local cookie =
                auth.set_cookie_header(
                    identity_name
                )

            if not cookie then
                send_json(res, 500, {
                    error =
                        "Unable to create identity cookie"
                })

                return
            end

            res:writeHead(200, {
                ["Content-Type"] =
                    "application/json; charset=utf-8",

                ["Cache-Control"] =
                    "no-cache",

                ["Set-Cookie"] =
                    cookie,
            })

            local response_body =
                json.encode({
                    identity =
                        identity_response(identity)
                })

            if not response_body then
                response_body =
                    '{"error":"Unable to encode server response"}'
            end

            res:finish(response_body)
        end
    )
end


local function handle_auth_status(req, res)
    local identity =
        auth.from_request(req)

    send_json(
        res,
        200,
        identity_response(identity)
    )
end


local function handle_login(req, res)
    read_request_body(
        req,
        function(body, body_error)

            if body_error then
                send_json(res, 400, {
                    error =
                        "Unable to read request: " ..
                        tostring(body_error)
                })

                return
            end

            local ok, data =
                pcall(
                    json.decode,
                    body
                )

            if not ok or
               type(data) ~= "table" then

                send_json(res, 400, {
                    error =
                        "Invalid JSON request"
                })

                return
            end

            -- The local provider deliberately simulates identity
            -- selection. It does not perform real authentication.
            --
            -- Expected:
            --
            -- {
            --     "identity": "mark"
            -- }

            local identity_name =
                data.identity

            if type(identity_name) ~= "string" or
               identity_name:match("^%s*$") then

                send_json(res, 400, {
                    error =
                        "Identity is required"
                })

                return
            end

            local identity =
                auth.get_identity(
                    identity_name
                )

            if not identity then
                send_json(res, 401, {
                    error =
                        "Unknown local identity"
                })

                return
            end

            local cookie =
                auth.set_cookie_header(
                    identity_name
                )

            if not cookie then
                send_json(res, 500, {
                    error =
                        "Unable to create identity cookie"
                })

                return
            end

            print(
                "[INFO] Local identity selected: " ..
                auth.describe(identity)
            )

            send_json(
                res,
                200,
                identity_response(identity),
                {
                    ["Set-Cookie"] = cookie,
                }
            )
        end
    )
end


local function handle_logout(req, res)
    auth.clear_session_cookie =
        auth.clear_session_cookie or
        function()
            return nil
        end

    local identity =
        auth.from_request(req)

    print(
        "[INFO] Local identity logged out: " ..
        auth.describe(identity)
    )

    send_json(
        res,
        200,
        {
            authenticated = false,
            anonymous = true,

            user = {
                id = "local-anonymous",
                name = "Anonymous",
                provider = "local",
            },
        },
        {
            ["Set-Cookie"] =
                auth.config.cookie_name ..
                "=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0",
        }
    )
end


local function handle_message(req, res)
    read_request_body(
        req,
        function(body, body_error)

            if body_error then
                send_json(res, 400, {
                    error =
                        "Unable to read request: " ..
                        tostring(body_error)
                })

                return
            end

            local ok, data =
                pcall(
                    json.decode,
                    body
                )

            if not ok or
               type(data) ~= "table" then

                send_json(res, 400, {
                    error =
                        "Invalid JSON request"
                })

                return
            end

            local input =
                data.message

            if type(input) ~= "string" or
               input:match("^%s*$") then

                send_json(res, 400, {
                    error =
                        "Message is required"
                })

                return
            end

            local identity

            -- A frontend may supply identity explicitly.
            --
            -- Discord uses this path because Discord itself knows
            -- which Discord user invoked the slash command.
            if type(data.identity) == "table" then
                identity =
                    identity_from_client(
                        data.identity
                    )

                if not identity then
                    send_json(res, 400, {
                        error =
                            "Invalid client identity"
                    })

                    return
                end

            else
                -- Web frontend continues to use the local simulated
                -- cookie identity.
                identity =
                    auth.from_request(req)
            end

            if not identity then
                identity =
                    auth.get_default()
            end

            local behaviors =
                sanitize_behaviors(
                    data.behaviors
                )

            local request_id = Observability.new_request_id()
            local request_context = Observability.new_context({
                request_id = request_id,
                user_id = identity and identity.user_id or nil,
                provider = identity and identity.provider or nil,
            })

            print(
                "[INFO] Processing web message..."
            )

            Observability.log("http_message", request_context, {
                method = req.method,
                path = req.url,
                input_bytes = #input,
                identity_status = Policy.identity_status(identity),
            })

            print(
                "[INFO] Identity: " ..
                tostring(identity.user_id) ..
                " (" ..
                tostring(identity.provider) ..
                ")"
            )

            print(
                "[INFO] Name: " ..
                tostring(identity.name)
            )

            alice.process_user_input(
                input,
                function(response, err)

                    if err then
                        Observability.error("http_message_failed", request_context, err)

                        print(
                            "[ERROR] " ..
                            tostring(err)
                        )

                        send_json(res, 502, {
                            error = tostring(err),
                            request_id = request_id,
                        })

                        return
                    end

                    print(
                        "[INFO] Ollama response returned"
                    )

                    Observability.log("http_message_completed", request_context, {
                        response_bytes = #(response or ""),
                    })

                    send_json(res, 200, {
                        response = response,
                        request_id = request_id,

                        user = {
                            id =
                                identity.user_id,

                            name =
                                identity.name,

                            email =
                                identity.email,

                            provider =
                                identity.provider,

                            anonymous =
                                identity.anonymous,
                        },
                    })
                end,
                behaviors,
                identity
            )
        end
    )
end


local function handle_request(req, res)
    if req.method == "GET" and
       req.url == "/" then

        local ok, html =
            pcall(
                fs.readFileSync,
                INDEX_FILE
            )

        if not ok then
            send_text(
                res,
                500,
                "Unable to read " ..
                INDEX_FILE ..
                ": " ..
                tostring(html)
            )

            return
        end

        res:writeHead(200, {
            ["Content-Type"] =
                "text/html; charset=utf-8",

            ["Content-Length"] =
                tostring(#html),

            ["Cache-Control"] =
                "no-cache",
        })

        res:finish(html)

        return
    end


    if req.method == "GET" and
       req.url == "/api/identity" then

        handle_identity_get(req, res)
        return
    end


    if req.method == "POST" and
       req.url == "/api/identity" then

        handle_identity_select(req, res)
        return
    end


    if req.method == "GET" and
       req.url == "/api/auth/status" then

        handle_auth_status(req, res)
        return
    end


    if req.method == "POST" and
       req.url == "/api/auth/login" then

        handle_login(req, res)
        return
    end


    if req.method == "POST" and
       req.url == "/api/auth/logout" then

        handle_logout(req, res)
        return
    end


    if req.method == "POST" and
       req.url == "/api/message" then

        handle_message(req, res)
        return
    end


    if req.method == "GET" and
       req.url == "/api/status" then

        local identity =
            auth.from_request(req)

        if not identity then
            identity =
                auth.get_default()
        end

        send_json(res, 200, {
            status = "ok",
            model = "gemma4:26b",

            identity = {
                id =
                    identity.user_id,

                authenticated =
                    identity.authenticated,

                anonymous =
                    identity.anonymous,

                provider =
                    identity.provider,
            },
        })

        return
    end


    send_text(
        res,
        404,
        "Not found"
    )
end


local server =
    http.createServer(
        handle_request
    )

server:listen(
    PORT,
    HOST
)

print(
    string.format(
        "[INFO] Alice server running on http://%s:%d",
        HOST,
        PORT
    )
)

print(
    "[INFO] Local authentication layer enabled"
)

print(
    "[INFO] Anonymous access is permitted"
)

