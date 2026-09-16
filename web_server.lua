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
--
-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- <https://www.gnu.org/licenses/>.

-- web_server.lua
-- Luvit HTTP server for Alice Web AI.
-- Lua 5.1 compatible.

local http = require("http")
local json = require("json")
local fs = require("fs")
local alice = require("./alice")

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

        local behaviors =
            sanitize_behaviors(
                data.behaviors
            )

        print(
            "[INFO] Processing web message..."
        )

        alice.process_user_input(
            input,
            function(response, err)

                if err then
                    print(
                        "[ERROR] " ..
                        tostring(err)
                    )

                    send_json(res, 502, {
                        error =
                            tostring(err)
                    })

                    return
                end

                print(
                    "[INFO] Ollama response returned"
                )

                send_json(res, 200, {
                    response = response
                })
            end,
            behaviors
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

if req.method == "POST" and
   req.url == "/api/message" then

    handle_message(req, res)
    return
end

if req.method == "GET" and
   req.url == "/api/status" then

    send_json(res, 200, {
        status = "ok",
        model = "gemma4:26b",
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
http.createServer(handle_request)

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
