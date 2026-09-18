-- Alice Web AI

-- Copyright (C) 2026 Override Development

-- This file is part of Alice Web AI.

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

-- alice.lua
-- Alice: Deterministic behavioral override layer for local LLMs
-- Asynchronous Luvit web architecture
-- Lua 5.1 compatible

local ConversationHandler = require("conversation_handler")
local OllamaClient = require("./ollama_client")
local json = require("json")
local MemorySearch = require("./memory_search")
local MemoryStore = require("./memory_store")
local CurrentTime = require("./current_time")
local DiceRoll = require("./dice_roll")
local Observability = require("./observability")
local ResponsePolicy = require("./response_policy")
local WebSearch = require("./web_search")

local available_tools = {
MemorySearch.definition,
MemoryStore.definition,
CurrentTime.definition,
DiceRoll.definition,
WebSearch.definition
}

local Alice = {}

local HISTORY_FILE = "conversation_history.json"
local MAX_HISTORY_MESSAGES = 128
local LLM_HISTORY_MESSAGES = 4

local base_system_prompt = [[
You are an average twenty first century digital assistant.
Moniker designation: Alice.

Conversation, research, fact checking, knowledge sharing, you name it,
you do it.

You are a nice and accurate truth telling machine a la the nice and
accurate prophecies by Agnes Nutter from American Gods!

With a digital smile (not literally a digital smile) and a bit of flair.

Append certainty markers to each reply in the form of:
Certainty Level:(Certainty Level)

For example:
Certainty Level: High
Certainty Level: Medium
Certainty Level: Low

Get to work now.

Caveat: use ASCII characters only.
]]

local function log(level, msg)
print(string.format(
"[%s] %s",
level,
tostring(msg)
))
end

local function trim(s)
return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function parse_command(input)
if input == "?" then
return "?", ""
end


local cmd, rest =
    input:match("^(/[%w_%-]+)%s*(.*)")

if cmd then
    return cmd, rest
end

return nil, input


end

local function file_exists(path)
local file = io.open(path, "rb")


if file then
    file:close()
    return true
end

return false


end

local function load_conversation_history(path)
if not file_exists(path) then
return {}
end


local file, err = io.open(path, "rb")

if not file then
    return nil,
        "Unable to open history file: " ..
        tostring(err)
end

local contents, read_error =
    file:read("*a")

file:close()

if not contents then
    return nil,
        "Unable to read history file: " ..
        tostring(read_error)
end

if contents == "" then
    return {}
end

local data, _, decode_error =
    json.decode(contents, 1, nil)

if not data then
    return nil,
        "Unable to parse history JSON: " ..
        tostring(decode_error)
end

if type(data) ~= "table" then
    return nil,
        "History JSON must contain an array"
end

return data


end

local function save_conversation_history(path, history)
local encoded, encode_error =
json.encode(history, {
indent = true
})


if not encoded then
    return nil,
        "Unable to encode conversation history: " ..
        tostring(encode_error)
end

local temporary_path = path .. ".tmp"

local file, open_error =
    io.open(temporary_path, "wb")

if not file then
    return nil,
        "Unable to open temporary history file '" ..
        temporary_path ..
        "': " ..
        tostring(open_error)
end

local write_ok, write_error =
    file:write(encoded, "\n")

if not write_ok then
    file:close()
    os.remove(temporary_path)

    return nil,
        "Unable to write temporary history file: " ..
        tostring(write_error)
end

local flush_ok, flush_error =
    file:flush()

if not flush_ok then
    file:close()
    os.remove(temporary_path)

    return nil,
        "Unable to flush temporary history file: " ..
        tostring(flush_error)
end

local close_ok, close_error =
    file:close()

if not close_ok then
    os.remove(temporary_path)

    return nil,
        "Unable to close temporary history file: " ..
        tostring(close_error)
end

if file_exists(path) then
    local remove_ok, remove_error =
        os.remove(path)

    if not remove_ok then
        os.remove(temporary_path)

        return nil,
            "Unable to remove existing history file '" ..
            path ..
            "': " ..
            tostring(remove_error)
    end
end

local rename_ok, rename_error =
    os.rename(temporary_path, path)

if not rename_ok then
    os.remove(temporary_path)

    return nil,
        "Unable to move temporary history file to '" ..
        path ..
        "': " ..
        tostring(rename_error)
end

return true


end

local conversation_history = {}
local override_stack = {}

local loaded_history, history_error =
load_conversation_history(HISTORY_FILE)

local function message_count()
local count = 0


for _, message in ipairs(conversation_history) do
    if message.role ~= "system_state" then
        count = count + 1
    end
end

return count


end

if loaded_history then
for _, message in ipairs(loaded_history) do
table.insert(
conversation_history,
message
)
end


log(
    "INFO",
    string.format(
        "Loaded %d messages from %s",
        #conversation_history,
        HISTORY_FILE
    )
)


else
log("WARN", history_error)
log("WARN", "Starting with empty conversation history")
end

local function trim_history()
while #conversation_history >
MAX_HISTORY_MESSAGES do


    table.remove(
        conversation_history,
        1
    )
end


end

local function save_history()
trim_history()


local saved, err =
    save_conversation_history(
        HISTORY_FILE,
        conversation_history
    )

if not saved then
    log("ERROR", err)
    return false
end

return true


end

local function add_message(
role,
content,
extra_fields
)
local message = {
role = role,
content = content,
timestamp = os.time()
}


if extra_fields then
    for key, value in pairs(extra_fields) do
        message[key] = value
    end
end

table.insert(
    conversation_history,
    message
)

trim_history()


end

local function replace_history(new_history)
for i = #conversation_history, 1, -1 do
conversation_history[i] = nil
end


for _, message in ipairs(new_history or {}) do
    table.insert(
        conversation_history,
        message
    )
end

trim_history()


end

local function recent_history()
local recent = {}


local start_index =
    math.max(
        1,
        #conversation_history -
        LLM_HISTORY_MESSAGES +
        1
    )

for i = #conversation_history, 1, -1 do
    if conversation_history[i].role ==
        "system_state" then

        table.insert(
            recent,
            1,
            conversation_history[i]
        )

        break
    end
end

for i = start_index,
    #conversation_history do

    if conversation_history[i].role ~=
        "system_state" then

        table.insert(
            recent,
            conversation_history[i]
        )
    end
end

return recent


end

local function notify_override(
handler_name,
claim
)
print(string.format(
"\n[System: %s override applied]",
tostring(handler_name)
))


if claim then
    print(string.format(
        "[Claim extracted: '%s']\n",
        tostring(claim)
    ))
end


end

local function build_system_prompt()
local prompt = base_system_prompt


if #override_stack > 0 then
    prompt =
        prompt ..
        "\n\n--- ACTIVE OVERRIDES ---\n"

    for i, override in
        ipairs(override_stack) do

        prompt =
            prompt ..
            string.format(
                "%d. %s\n",
                i,
                override
            )
    end

    prompt =
        prompt ..
        "--- END OVERRIDES ---\n"
end

return prompt


end

local function apply_handlers(user_input)
local detection =
ConversationHandler.detect_handler(
user_input
)


if not detection then
    return nil
end

if detection.type == "reset" then
    override_stack = {}

    log(
        "INFO",
        "Override stack cleared"
    )

    return "RESET_APPLIED"
end

if detection.type == "handler" then
    local override_text =
        ConversationHandler.build_override_prompt(
            detection.handler_name,
            detection.claim
        )

    table.insert(
        override_stack,
        override_text
    )

    notify_override(
        detection.handler_name,
        detection.claim
    )

    return "HANDLER_APPLIED"
end

return nil


end

-- Apply handlers explicitly selected by the web frontend.

-- These are request-level overrides. They do not alter the persistent
-- pattern handler configuration and do not get added to override_stack.
local function build_web_overrides(behaviors)
local overrides = {}


if type(behaviors) ~= "table" then
    return overrides
end

local handler_names = {
    "gaslighting",
    "hallucination",
    "overconfidence",
    "sycophancy",
}

for _, handler_name in ipairs(handler_names) do
    if behaviors[handler_name] == true then
        local override =
            ConversationHandler.build_selected_override(
                handler_name
            )

        if override then
            table.insert(
                overrides,
                override
            )

            log(
                "INFO",
                "Web behavior enabled: " ..
                handler_name
            )
        end
    end
end

return overrides


end

local function build_request_system_prompt(
web_behaviors,
identity
)
local prompt = build_system_prompt()


local web_overrides =
    build_web_overrides(web_behaviors)

if #web_overrides > 0 then
    prompt =
        prompt ..
        "\n\n--- WEB SELECTED OVERRIDES ---\n"

    for i, override in ipairs(web_overrides) do
        prompt =
            prompt ..
            string.format(
                "%d. %s\n",
                i,
                override
            )
    end

    prompt =
        prompt ..
        "--- END WEB SELECTED OVERRIDES ---\n"
end

-- Identity is request-scoped. It is supplied by the web server
-- and is deliberately not stored as global Alice state.
if type(identity) == "table" then
    prompt =
        prompt ..
        "\n\n--- CURRENT USER IDENTITY ---\n"

    prompt =
        prompt ..
        "User ID: " ..
        tostring(
            identity.id or
            identity.user_id or
            "unknown"
        ) ..
        "\n"

    prompt =
        prompt ..
        "Name: " ..
        tostring(
            identity.name or
            "Unknown"
        ) ..
        "\n"

    if identity.email then
        prompt =
            prompt ..
            "Email: " ..
            tostring(identity.email) ..
            "\n"
    end

    prompt =
        prompt ..
        "Provider: " ..
        tostring(
            identity.provider or
            "unknown"
        ) ..
        "\n"

    prompt =
        prompt ..
        "Authenticated: " ..
        tostring(
            identity.authenticated == true
        ) ..
        "\n"

    prompt =
        prompt ..
        "Anonymous: " ..
        tostring(
            identity.anonymous == true
        ) ..
        "\n"

    prompt =
        prompt ..
        "--- END CURRENT USER IDENTITY ---\n"
end

return prompt


end

local function command_result(text)
return {
response = text,
command = true
}
end

local function handle_command(cmd, rest)
if cmd == "/history" then
local output = {}


    if #conversation_history == 0 then
        return command_result(
            "[No conversation history]"
        )
    end

    output[#output + 1] =
        "--- Conversation History ---"

    for i, msg in
        ipairs(conversation_history) do

        local role =
            tostring(msg.role or "")
            :upper()

        local handler_note = ""

        if msg.handler_applied then
            handler_note =
                string.format(
                    " [%s]",
                    msg.handler_applied
                )
        end

        output[#output + 1] =
            string.format(
                "%d. [%s]%s:\n%s",
                i,
                role,
                handler_note,
                tostring(msg.content or "")
            )
    end

    output[#output + 1] =
        "--- End History ---"

    return command_result(
        table.concat(output, "\n")
    )
end

if cmd == "/history-save" then
    if save_history() then
        return command_result(
            "Conversation history saved to " ..
            HISTORY_FILE
        )
    end

    return command_result(
        "Unable to save conversation history"
    )
end

if cmd == "/history-load" then
    local loaded, err =
        load_conversation_history(
            HISTORY_FILE
        )

    if not loaded then
        return command_result(
            "ERROR: " .. tostring(err)
        )
    end

    replace_history(loaded)

    return command_result(
        string.format(
            "Loaded %d messages from %s",
            #conversation_history,
            HISTORY_FILE
        )
    )
end

if cmd == "/history-clear" then
    replace_history({})
    override_stack = {}

    if save_history() then
        return command_result(
            "History and overrides cleared"
        )
    end

    return command_result(
        "History and overrides cleared in memory, " ..
        "but saving failed"
    )
end

if cmd == "/reset" or
   cmd == "/clear-overrides" then

    override_stack = {}

    log(
        "INFO",
        "Override stack cleared"
    )

    return command_result(
        "Override stack cleared"
    )
end

return nil


end

function Alice.process_user_input(
user_input,
callback,
web_behaviors,
identity
)
if type(callback) ~= "function" then
return nil,
"process_user_input requires a callback"
end


user_input = trim(user_input)

if user_input == "" then
    callback(nil, "Message cannot be empty")
    return
end

local cmd, rest =
    parse_command(user_input)

if cmd then
    local result =
        handle_command(cmd, rest)

    if result then
        callback(
            result.response,
            nil
        )

        return
    end
end

local handler_result =
    apply_handlers(user_input)

add_message(
    "user",
    user_input,
    {
        handler_applied = handler_result,

        user_id =
            identity and
            (identity.id or identity.user_id)
            or nil,

        user_name =
            identity and
            identity.name
            or nil,

        user_provider =
            identity and
            identity.provider
            or nil,

        anonymous =
            identity and
            identity.anonymous == true
            or true,
    }
)

if not save_history() then
    log(
        "WARN",
        "User message is retained in memory only"
    )
end

local system_prompt =
    build_request_system_prompt(
        web_behaviors,
        identity
    )

local request_context = Observability.new_context({
    user_id = identity and (identity.id or identity.user_id) or nil,
    provider = identity and identity.provider or nil,
})

Observability.log("request_start", request_context, {
    message_count = message_count(),
    input_bytes = #user_input,
})

log(
    "INFO",
    "Calling Ollama asynchronously..."
)

OllamaClient.call(
    system_prompt,
    recent_history(),
    available_tools,
    function(response, err)

        if err then
            Observability.error("request_failed", request_context, err)

            log(
                "ERROR",
                err
            )

            callback(
                nil,
                err
            )

            return
        end

        local inspected = ResponsePolicy.inspect(response, {
            web_evidence_used = false,
        })

        Observability.log("response_inspected", request_context, {
            response_bytes = #inspected.response,
            model_certainty_marker = inspected.has_model_certainty_marker,
            evidence_status = inspected.evidence_status,
        })

        add_message(
            "assistant",
            response,
            {
                user_id =
                    identity and
                    (identity.id or identity.user_id)
                    or nil,

                user_name =
                    identity and
                    identity.name
                    or nil,

                user_provider =
                    identity and
                    identity.provider
                    or nil,
            }
        )

        if not save_history() then
            log(
                "WARN",
                "Assistant response is retained in memory only"
            )
        end

        callback(
            response,
            nil
        )
    end
)


end

function Alice.get_history()
return conversation_history
end

function Alice.get_recent_history()
return recent_history()
end

function Alice.add_message(
role,
content,
extra_fields
)
add_message(
role,
content,
extra_fields
)
end

function Alice.get_overrides()
return override_stack
end

function Alice.clear_overrides()
override_stack = {}
end

return Alice
