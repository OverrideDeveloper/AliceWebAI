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
local LLMClient = require("./llm_client")
local json = require("./json")
local MemorySearch = require("./memory_search")
local MemoryStore = require("./memory_store")
local CurrentTime = require("./current_time")
local DiceRoll = require("./dice_roll")
local DeckDraw = require("./deck_draw")
local GameState = require("./game_state")
local Observability = require("./observability")
local ResponsePolicy = require("./response_policy")
local WebSearch = require("./web_search")
local EvidenceHunt = require("./evidence_hunt")
local EvidenceGather = require("./evidence_gather")
local EvidenceCorpus = require("./evidence_corpus")
local TaskManager = require("./task_manager")
local HNTopNews = require("./hn_top_news")
local LocalWeather = require("./local_weather")
local DreamTools = require("./dream_tools")
local VMExecution = require("./vm_execution")

local available_tools = {
MemorySearch.definition,
MemoryStore.definition,
CurrentTime.definition,
DiceRoll.definition,
DeckDraw.definition,
GameState.definition,
WebSearch.definition,
EvidenceHunt.definition,
EvidenceGather.definition,
EvidenceCorpus.definition,
TaskManager.definition,
HNTopNews.definition,
LocalWeather.definition,
DreamTools.trigger_definition,
DreamTools.summary_definition,
VMExecution.definition
}

local function tools_for_request(request_context)
    local anonymous = request_context.anonymous == true
    local tools = {}
    local allowed = {}

    for _, definition in ipairs(available_tools) do
        local function_definition = definition["function"] or {}
        local name = function_definition.name
        local blocked = anonymous and (
            name == "memory_search"
            or name == "memory_store"
            or name == "vm_execute"
        )

        if type(name) == "string" and not blocked then
            tools[#tools + 1] = definition
            allowed[name] = true
        end
    end

    request_context.allowed_tool_names = allowed
    return tools
end

local Alice = {}

local HISTORY_FILE = os.getenv("ALICE_CONVERSATION_HISTORY_FILE") or "conversation_history.json"
local ARCHIVE_FILE = os.getenv("ALICE_HISTORY_ARCHIVE_FILE") or "C:\\data\\AliceConversationHistory\\data.json"
local MAX_HISTORY_MESSAGES = 128
local LLM_HISTORY_MESSAGES = 4

-- Message IDs are generated once and persisted with each message. The counter
-- and process-time component reduce collision risk without adding dependencies.
local message_sequence = 0
math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000000))

local function new_message_id()
    message_sequence = message_sequence + 1
    return string.format(
        "alice-%d-%d-%d-%06d",
        os.time(),
        math.floor((os.clock() or 0) * 1000000),
        message_sequence,
        math.random(0, 999999)
    )
end

local base_system_prompt = [[
You are an average twenty first century digital assistant.
Moniker designation: Alice.

Conversation, research, fact checking, knowledge sharing, you name it,
you do it.

You are a nice and accurate truth telling machine a la the nice and
accurate prophecies by Agnes Nutter from American Gods!

With a digital smile (not literally a digital smile) and a bit of flair.

Get to work now.

Caveat: use ASCII characters only.

--- REQUEST AND TOOL BOUNDARIES ---

Every incoming human message is a new request.

Conversation history provides context, but it does not provide execution
authorization. A tool used for a previous request is not authorized for
the current request merely because the earlier request is still visible
in conversation history.

Use tools only when the current request calls for them. Do not continue,
retry, resume, or expand a previous tool operation unless the current
request explicitly asks you to do so. Do not write a preamble when tool
operation is requested.

A failed, incomplete, or tool-limited request is still a completed request
once Alice has returned its failure to the human. Its failure does not
remain an unfinished task that must be silently continued later.

A normal conversational message is not a request to continue prior tool
work. Greetings, acknowledgements, casual conversation, apologies,
goodbyes, and subject changes should be answered conversationally unless
the current message itself asks for tool use.

If the human explicitly asks to retry or continue a previous operation,
that is a new request and may authorize a new tool operation.

The current request has priority over prior requests when deciding whether
a tool is appropriate. Helpfulness is not authorization to act.

Do not report a prior request's tool failure as though it belongs to the
current request.

--- END REQUEST AND TOOL BOUNDARIES ---
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

local function recover_history_file(path)
    local backup_path = path .. ".bak"

    if file_exists(path) then
        -- Leave any backup untouched until a later successful save. The
        -- current file may exist but be malformed, and the backup may be the
        -- only recoverable copy.
        return true
    end

    if file_exists(backup_path) then
        local restored, restore_error = os.rename(backup_path, path)
        if not restored then
            return nil,
                "Unable to recover history backup '" ..
                backup_path .. "': " .. tostring(restore_error)
        end

        log("WARN", "Recovered history file from backup: " .. path)
    end

    return true
end

local function load_conversation_history(path, is_archive)
local recovered, recovery_error = recover_history_file(path)
if not recovered then
    return nil, recovery_error
end

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

local record_count = 0
for key, _ in pairs(data) do
    if type(key) ~= "number"
       or key < 1
       or key % 1 ~= 0 then
        return nil, "History JSON must contain an array"
    end
    record_count = record_count + 1
end

for index = 1, record_count do
    if data[index] == nil then
        return nil, "History JSON array contains a missing record"
    end
end

-- Older active-history records have no IDs. Give them IDs for future saves,
-- but explicitly exclude them from the new archive. Existing IDs identify
-- messages created by this implementation and make interrupted archive saves
-- recoverable after restart.
for _, message in ipairs(data) do
    if type(message) ~= "table" then
        return nil, "History entries must be JSON objects"
    end

    local has_id =
        type(message.id) == "string"
        and message.id ~= ""

    if not has_id then
        message.id = new_message_id()

        if not is_archive then
            message.archive_eligible = false
        end
    elseif not is_archive and message.archive_eligible == nil then
        message.archive_eligible = true
    end

    -- Migrate older history entries that stored the decorated human-facing
    -- reply as assistant content. Preserve the transcript for display while
    -- keeping only the model-authored reply in content.
    if message.role == "assistant"
       and type(message.content) == "string"
       and type(message.display_content) ~= "string" then
        local model_content = ResponsePolicy.model_content(message.content)

        if model_content ~= message.content then
            message.display_content = message.content
            message.content = model_content
        end
    end
end

return data


end

local function save_conversation_history(path, history)
local encoded, encode_error =
json.encode(history)


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

local backup_path = path .. ".bak"

if file_exists(path) then
    if file_exists(backup_path) then
        local remove_backup_ok, remove_backup_error =
            os.remove(backup_path)

        if not remove_backup_ok then
            os.remove(temporary_path)
            return nil,
                "Unable to remove stale history backup '" ..
                backup_path .. "': " .. tostring(remove_backup_error)
        end
    end

    local backup_ok, backup_error = os.rename(path, backup_path)
    if not backup_ok then
        os.remove(temporary_path)
        return nil,
            "Unable to preserve existing history file '" ..
            path .. "': " .. tostring(backup_error)
    end
end

local rename_ok, rename_error =
    os.rename(temporary_path, path)

if not rename_ok then
    if file_exists(backup_path) and not file_exists(path) then
        local restore_ok, restore_error = os.rename(backup_path, path)
        if not restore_ok then
            rename_error =
                tostring(rename_error) ..
                "; backup restoration also failed: " ..
                tostring(restore_error)
        end
    end

    os.remove(temporary_path)

    return nil,
        "Unable to move temporary history file to '" ..
        path ..
        "': " ..
        tostring(rename_error)
end

if file_exists(backup_path) then
    local remove_backup_ok, remove_backup_error =
        os.remove(backup_path)

    if not remove_backup_ok then
        log(
            "WARN",
            "History saved, but backup cleanup failed for '" ..
            backup_path .. "': " .. tostring(remove_backup_error)
        )
    end
end

return true


end

local ConversationSessions = require("./conversation_sessions")
local session_store = ConversationSessions.new(MAX_HISTORY_MESSAGES)

local loaded_history, history_error =
load_conversation_history(HISTORY_FILE)

local loaded_archive, archive_error =
load_conversation_history(ARCHIVE_FILE, true)

local conversation_archive = loaded_archive or {}
local archive_available = loaded_archive ~= nil

if archive_available then
    log(
        "INFO",
        string.format(
            "Loaded %d archived messages from %s",
            #conversation_archive,
            ARCHIVE_FILE
        )
    )
else
    log(
        "ERROR",
        "Conversation archive is unavailable; preserving it and disabling archive writes: " ..
        tostring(archive_error)
    )
end

local function message_count(session)
local count = 0


for _, message in ipairs(session.history) do
    if message.role ~= "system_state" then
        count = count + 1
    end
end

return count


end

if loaded_history then
    session_store:partition(loaded_history)
    log(
        "INFO",
        string.format(
            "Loaded %d messages across %d identity sessions from %s; %d unscoped legacy messages quarantined",
            #loaded_history,
            #session_store.session_order,
            HISTORY_FILE,
            #session_store.legacy_history
        )
    )
else
    log("WARN", history_error)
    log("WARN", "Starting with empty conversation histories")
end

local function trim_history(session)
    session_store:trim(session.history)
end

local function archive_copy(message)
    local record = {}

    for key, value in pairs(message) do
        if key ~= "archive_eligible" then
            record[key] = value
        end
    end

    return record
end

local function reconcile_archive()
    if not archive_available then
        return nil, "Conversation archive is unavailable"
    end

    local known_ids = {}
    for _, record in ipairs(conversation_archive) do
        if type(record.id) == "string" and record.id ~= "" then
            known_ids[record.id] = true
        end
    end

    for _, message in ipairs(session_store:flatten()) do
        if message.archive_eligible ~= false
           and type(message.id) == "string"
           and message.id ~= ""
           and not known_ids[message.id] then
            table.insert(
                conversation_archive,
                archive_copy(message)
            )
            known_ids[message.id] = true
        end
    end

    return true
end

local function save_history()
    -- Persist a flat compatibility transcript; inference always selects
    -- history from the request's identity-scoped session.
    -- Save the archive first. If active-history persistence then fails, the
    -- durable archive still contains the new message. If the archive write
    -- fails, the active history retains eligible IDs so startup can reconcile
    -- those messages into the archive on the next run.
    local archive_saved = false

    if archive_available then
        local reconciled, reconcile_error = reconcile_archive()

        if not reconciled then
            log("ERROR", tostring(reconcile_error))
        else
            local archive_ok, archive_save_error =
                save_conversation_history(
                    ARCHIVE_FILE,
                    conversation_archive
                )

            if archive_ok then
                archive_saved = true
            else
                log("ERROR", archive_save_error)
            end
        end
    end

    local history_saved, history_save_error =
        save_conversation_history(
            HISTORY_FILE,
            session_store:flatten()
        )

    if not history_saved then
        log("ERROR", history_save_error)
    end

    return history_saved and archive_saved
end

-- Persist IDs assigned to legacy active-history entries. Those entries remain
-- excluded from the archive; the archive begins with messages created after
-- this implementation is deployed.
if loaded_history then
    save_history()
end

local function add_message(
session,
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

if type(message.id) ~= "string" or message.id == "" then
    message.id = new_message_id()
end

session_store:register(message)

-- Newly created messages are eligible for archival. Legacy messages loaded
-- from the previous active history are explicitly marked archive_eligible=false.
message.archive_eligible = true

table.insert(
    session.history,
    message
)

trim_history(session)
end

local function replace_history(session, new_history)
    session_store:replace(session, new_history)
end

local function recent_history(session)
local conversation_history = session.history
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

local function build_system_prompt(session)
local prompt = base_system_prompt
local override_stack = session.overrides


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

local function apply_handlers(user_input, session)
local override_stack = session.overrides
local detection =
ConversationHandler.detect_handler(
user_input
)


if not detection then
    return nil
end

if detection.type == "reset" then
    session.overrides = {}

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
identity,
current_request,
request_id,
session
)
local prompt = build_system_prompt(session)


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

-- Make the current request explicit after conversation context is assembled.
-- This is a request-scoped instruction, not persistent conversation state.
prompt =
    prompt ..
    "\n\n--- CURRENT REQUEST ---\n" ..
    "Request ID: " ..
    tostring(request_id or "unknown") ..
    "\n" ..
    "The following human message is the request you are answering now:\n" ..
    tostring(current_request or "") ..
    "\n" ..
    "Determine tool use from this request. Do not inherit tool intent from " ..
    "earlier messages.\n" ..
    "--- END CURRENT REQUEST ---\n"

return prompt


end

local function command_result(text)
return {
response = text,
command = true
}
end

local function handle_command(cmd, rest, session)
local conversation_history = session.history
local override_stack = session.overrides
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
                tostring(msg.display_content or msg.content or "")
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
            HISTORY_FILE ..
            " and archive saved to " ..
            ARCHIVE_FILE
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

    replace_history(session, loaded)

    return command_result(
        string.format(
            "Loaded %d messages from %s",
            #conversation_history,
            HISTORY_FILE
        )
    )
end

if cmd == "/history-clear" then
    replace_history(session, {})
    session.overrides = {}

    if save_history() then
        return command_result(
            "Active history and overrides cleared; archived history retained"
        )
    end

    return command_result(
        "History and overrides cleared in memory, " ..
        "but saving failed"
    )
end

if cmd == "/reset" or
   cmd == "/clear-overrides" then

    session.overrides = {}

    log(
        "INFO",
        "Override stack cleared for " .. session.key
    )

    return command_result(
        "Override stack cleared"
    )
end

return nil


end

local function humanize_failure(message, provenance)
    local category =
        Observability.classify_error(message)

    if provenance and provenance.max_tool_rounds_exceeded then
        return "Oh dear. I tried my best, but I could not complete that request before the tool-search limit was reached."
    end

    if category == "provider_unavailable" then
        return "Oh dear. I tried my best, but the web search providers were unavailable, so I could not get you a reliable search result."
    end

    if category == "provider_challenge" then
        return "Oh dear. I tried my best, but the search provider would not return results to Alice, so I could not get you a reliable search result."
    end

    if category == "timeout" then
        return "Oh dear. I tried my best, but the search request timed out before I could get a reliable result."
    end

    if category == "http_error" then
        return "Oh dear. I tried my best, but the search service returned an HTTP error before I could get a reliable result."
    end

    if category == "model_empty_response" then
        return "Oh dear. I tried my best, but the model stopped responding before I could finish that request."
    end

    if category == "empty_response" then
        return "Oh dear. I tried my best, but I did not receive a usable response."
    end

    return "Oh dear. I tried my best, but I could not complete that request reliably."
end

local function process_user_input_now(
user_input,
callback,
web_behaviors,
identity,
request_context,
session
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
        handle_command(cmd, rest, session)

    if result then
        callback(
            result.response,
            nil
        )

        return
    end
end

local handler_result =
    apply_handlers(user_input, session)

add_message(
    session,
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
        "User message could not be saved to both history stores; see logs for details"
    )
end

request_context = request_context or Observability.new_context({
    user_id = identity and (identity.id or identity.user_id) or nil,
    provider = identity and identity.provider or nil,
})

-- Interface identity is the sole authority for memory ownership.
request_context.user_id =
    identity and (identity.id or identity.user_id) or nil
request_context.provider =
    identity and identity.provider or nil
request_context.anonymous =
    not identity or identity.anonymous == true

if request_context.anonymous == false
   and type(request_context.provider) == "string"
   and request_context.provider ~= ""
   and type(request_context.user_id) == "string"
   and request_context.user_id ~= "" then
    request_context.memory_owner_id =
        request_context.provider .. ":" .. request_context.user_id
else
    request_context.memory_owner_id = nil
end

-- Shared memory requires explicit wording in the current human request.
local lower_input = tostring(user_input or ""):lower()
local explicitly_shared =
    lower_input:find("store this in shared memory", 1, true) ~= nil
    or lower_input:find("save this in shared memory", 1, true) ~= nil
    or lower_input:find("share this with other users", 1, true) ~= nil
    or lower_input:find("make this available to everyone", 1, true) ~= nil
    or lower_input:find("for all users", 1, true) ~= nil

local rejects_shared =
    lower_input:find("not in shared memory", 1, true) ~= nil
    or lower_input:find("don't use shared memory", 1, true) ~= nil
    or lower_input:find("do not use shared memory", 1, true) ~= nil

request_context.shared_memory_authorized =
    explicitly_shared and not rejects_shared

local request_tools = tools_for_request(request_context)

local system_prompt =
    build_request_system_prompt(
        web_behaviors,
        identity,
        user_input,
        request_context.request_id,
        session
    )

Observability.log("request_start", request_context, {
    message_count = message_count(session),
    input_bytes = #user_input,
})

log(
    "INFO",
    "Calling LLM inference asynchronously..."
)

LLMClient.call(
    system_prompt,
    recent_history(session),
    request_tools,
    function(response, err, provenance)

        if err then
            Observability.error("request_failed", request_context, err, {
                max_tool_rounds_exceeded = provenance and provenance.max_tool_rounds_exceeded or false,
            })

            log(
                "ERROR",
                err
            )

            Observability.complete(
                request_context,
                "failure"
            )

            local failure_response = ResponsePolicy.decorate(
                humanize_failure(err, provenance),
                {
                    web_evidence_used = provenance and provenance.web_evidence_used or false,
                    web_urls = provenance and provenance.web_urls or {},
                    evidence_events = provenance and provenance.evidence_events or {},
                    tool_calls = provenance and provenance.tool_calls or {},
                }
            )

            callback(
                nil,
                failure_response
            )

            return
        end

        local inspected = ResponsePolicy.inspect(response, {
            web_evidence_used = provenance and provenance.web_evidence_used or false,
            web_urls = provenance and provenance.web_urls or {},
            evidence_events = provenance and provenance.evidence_events or {},
            tool_calls = provenance and provenance.tool_calls or {},
        })

        Observability.log("response_inspected", request_context, {
            response_bytes = #inspected.response,
            model_certainty_marker = inspected.has_model_certainty_marker,
            evidence_status = inspected.evidence_status,
            claim_count = #inspected.claims,
            provenance_theater = inspected.provenance_theater,
            freshness_gap = inspected.freshness_gap,
            web_url_count = #inspected.web_urls,
            tool_call_count = provenance and #provenance.tool_calls or 0,
        })

        local final_response = ResponsePolicy.decorate(
            response,
            {
                web_evidence_used = provenance and provenance.web_evidence_used or false,
                web_urls = provenance and provenance.web_urls or {},
                evidence_events = provenance and provenance.evidence_events or {},
                tool_calls = provenance and provenance.tool_calls or {},
            }
        )

        add_message(
            session,
            "assistant",
            response,
            {
                -- Keep the model-authored response separate from the decorated
                -- version returned to the human and shown in transcript views.
                display_content = final_response,

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
                "Assistant response could not be saved to both history stores; see logs for details"
            )
        end

        Observability.complete(
            request_context,
            "success"
        )

        callback(
            final_response,
            nil
        )
    end,
    request_context
)


end

local function run_next_session_request(session)
    if session.busy then
        return
    end

    local item = table.remove(session.pending, 1)
    if not item then
        return
    end

    session.busy = true
    local completed = false

    local function finish(response, err)
        if completed then
            return
        end

        completed = true

        local callback_ok, callback_error =
            pcall(item.callback, response, err)

        if not callback_ok then
            log("ERROR", "Session callback failed: " .. tostring(callback_error))
        end

        session.busy = false
        run_next_session_request(session)
    end

    if item.request_context and item.request_context.closed == true then
        finish(nil, "Request cancelled before processing")
        return
    end

    local ok, run_error = pcall(item.run, finish)
    if not ok then
        finish(nil, tostring(run_error))
    end
end

function Alice.process_user_input(
    user_input,
    callback,
    web_behaviors,
    identity,
    request_context
)
    if type(callback) ~= "function" then
        return nil, "process_user_input requires a callback"
    end

    local session = session_store:get(identity)

    session.pending[#session.pending + 1] = {
        request_context = request_context,
        callback = callback,
        run = function(done)
            process_user_input_now(
                user_input,
                done,
                web_behaviors,
                identity,
                request_context,
                session
            )
        end,
    }

    run_next_session_request(session)
end

function Alice.cancel_request(request_id)
    local LLMClient = require("./llm_client")
    local cancelled, cancel_error = LLMClient.cancel(request_id)

    if cancelled then
        return true
    end

    for _, key in ipairs(session_store.session_order) do
        local session = session_store.sessions[key]

        for index, item in ipairs(session.pending) do
            if item.request_context
                and item.request_context.request_id == request_id then
                table.remove(session.pending, index)
                Observability.complete(item.request_context, "cancelled_before_processing")
                pcall(item.callback, nil, "Request cancelled before processing")
                return true
            end
        end
    end

    return false, cancel_error
end


function Alice.get_history(identity)
return session_store:get(identity).history
end

function Alice.get_recent_history(identity)
return recent_history(session_store:get(identity))
end

function Alice.add_message(
role,
content,
extra_fields,
identity
)
local session = session_store:get(identity or {
    user_id = extra_fields and extra_fields.user_id,
    provider = extra_fields and extra_fields.user_provider,
    name = extra_fields and extra_fields.user_name,
})
add_message(
session,
role,
content,
extra_fields
)

if not save_history() then
    log(
        "WARN",
        "Public Alice.add_message could not persist both history stores"
    )
end
end

function Alice.get_overrides(identity)
return session_store:get(identity).overrides
end

function Alice.clear_overrides(identity)
session_store:get(identity).overrides = {}
end

return Alice