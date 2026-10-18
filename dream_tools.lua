-- Alice Web AI
-- Bounded, topic-driven contemplation sessions for Alice.
-- Lua 5.1 / Luvit compatible. Licensed under GPL-3.0-or-later.

local json = require("./json")
local MemorySearch = require("./memory_search")
local Observability = require("./observability")
local fs = require("fs")

local M = {}
M.storage_dir = "dreams"
M.default_max_turns = 16
M.hard_max_turns = 32
M.default_summary_interval = 8

local MEMORY_SEARCH_INTERVAL = 5
local RECENT_TURNS = 4
local prompt_variants = {
    "Ponder the topic before you and reflect upon it further.",
    "Continue contemplating this subject. What else deserves consideration?",
    "Reflect upon the ideas explored so far and continue your contemplation.",
    "Consider the topic from another perspective and ponder what follows.",
    "Return to the central subject. What connections or questions emerge?",
    "Continue reflecting on the topic, including questions that remain unresolved.",
    "Examine the subject again. What useful distinction or possibility remains unexplored?",
    "Pause over the current ideas and continue without forcing a conclusion.",
    "Look for a connection between the subject and what has emerged during this dream.",
    "Keep pondering the original topic. Which assumptions or possibilities merit another look?",
}

local random_seeded = false
local function seed_random()
    if random_seeded then return end
    math.randomseed(os.time() + math.floor(os.clock() * 100000))
    math.random(); math.random(); math.random()
    random_seeded = true
end

local function choose_prompt()
    seed_random()
    return prompt_variants[math.random(1, #prompt_variants)]
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function copy_json_value(value)
    local encoded = json.encode(value)
    if not encoded then return tostring(value) end
    local decoded = json.decode(encoded, 1, nil)
    if decoded ~= nil then return decoded end
    return encoded
end

local function validate_arguments(arguments)
    if type(arguments) ~= "table" then
        return nil, "dream_trigger arguments must be an object"
    end

    local topic = trim(arguments.topic)
    if topic == "" then return nil, "topic is required" end
    if #topic > 4000 then return nil, "topic must be 4000 bytes or fewer" end

    local memory_query = trim(arguments.memory_search_query)
    if memory_query == "" then return nil, "memory_search_query is required" end
    if #memory_query > 2000 then
        return nil, "memory_search_query must be 2000 bytes or fewer"
    end

    local max_turns = arguments.max_turns
    if max_turns == nil then
        max_turns = M.default_max_turns
    elseif type(max_turns) ~= "number" or max_turns % 1 ~= 0 or max_turns < 1 then
        return nil, "max_turns must be a positive integer when supplied"
    else
        max_turns = math.min(max_turns, M.hard_max_turns)
    end

    local summary_interval = arguments.summary_interval
    if summary_interval == nil then
        summary_interval = M.default_summary_interval
    elseif type(summary_interval) ~= "number"
        or summary_interval % 1 ~= 0 or summary_interval < 1 then
        return nil, "summary_interval must be a positive integer when supplied"
    else
        summary_interval = math.min(summary_interval, M.hard_max_turns)
    end

    return {
        topic = topic,
        memory_search_query = memory_query,
        max_turns = max_turns,
        summary_interval = summary_interval,
    }
end

local function safe_dream_id(value)
    return type(value) == "string" and #value >= 1 and #value <= 80
        and value:match("^[%w_-]+$") ~= nil
end

local function artifact_path(dream_id)
    return M.storage_dir .. "/dream_" .. dream_id .. ".json"
end

local function file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function save_artifact(artifact)
    -- Existing directories raise on mkdir; the subsequent file open verifies access.
    pcall(fs.mkdirSync, M.storage_dir)
    artifact.updated_at = os.time()

    local encoded, encode_error = json.encode(artifact)
    if not encoded then
        return nil, "Unable to encode dream artifact: " .. tostring(encode_error)
    end

    local path = artifact_path(artifact.dream_id)
    local temporary_path = path .. ".tmp"
    local file, open_error = io.open(temporary_path, "wb")
    if not file then
        return nil, "Unable to open temporary dream artifact: " .. tostring(open_error)
    end

    local write_ok, write_error = file:write(encoded, "\n")
    if not write_ok then
        file:close(); os.remove(temporary_path)
        return nil, "Unable to write dream artifact: " .. tostring(write_error)
    end
    local flush_ok, flush_error = file:flush()
    if not flush_ok then
        file:close(); os.remove(temporary_path)
        return nil, "Unable to flush dream artifact: " .. tostring(flush_error)
    end
    local close_ok, close_error = file:close()
    if not close_ok then
        os.remove(temporary_path)
        return nil, "Unable to close dream artifact: " .. tostring(close_error)
    end

    if file_exists(path) then
        local remove_ok, remove_error = os.remove(path)
        if not remove_ok then
            os.remove(temporary_path)
            return nil, "Unable to replace dream artifact: " .. tostring(remove_error)
        end
    end
    local rename_ok, rename_error = os.rename(temporary_path, path)
    if not rename_ok then
        os.remove(temporary_path)
        return nil, "Unable to finalize dream artifact: " .. tostring(rename_error)
    end
    return true
end

local function load_artifact(dream_id)
    if not safe_dream_id(dream_id) then
        return nil, "dream_id may contain only letters, digits, underscores, or hyphens"
    end
    local file, open_error = io.open(artifact_path(dream_id), "rb")
    if not file then return nil, "Unable to open dream artifact: " .. tostring(open_error) end
    local contents, read_error = file:read("*a")
    file:close()
    if not contents then return nil, "Unable to read dream artifact: " .. tostring(read_error) end

    local artifact, _, decode_error = json.decode(contents, 1, nil)
    if type(artifact) ~= "table" then
        return nil, "Unable to parse dream artifact: " .. tostring(decode_error)
    end
    if artifact.dream_id ~= dream_id then
        return nil, "Dream artifact identifier did not match the requested dream_id"
    end
    return artifact
end

local function new_dream_id()
    seed_random()
    local id
    repeat
        id = os.date("!%Y%m%dT%H%M%S") .. "-" .. tostring(math.random(100000, 999999))
    until not file_exists(artifact_path(id))
    return id
end

local function truncate(value, limit)
    local text = type(value) == "string" and value or (json.encode(value) or tostring(value))
    if #text > limit then return text:sub(1, limit) .. "... [truncated for summary]" end
    return text
end

local function summary_input(artifact)
    local output = {
        "Dream topic: " .. tostring(artifact.topic or ""),
        "Memory search query: " .. tostring(artifact.memory_search_query or ""),
        "Completed exploration turns: " .. tostring(artifact.turns_completed or 0),
        "",
        "Recorded turns:",
    }

    for _, turn in ipairs(artifact.turns or {}) do
        output[#output + 1] = string.format(
            "Turn %d prompt: %s", tonumber(turn.number) or 0,
            truncate(turn.prompt or "", 1200)
        )
        if turn.response then
            output[#output + 1] = "Turn response: " .. truncate(turn.response, 2200)
        elseif turn.error then
            output[#output + 1] = "Turn error: " .. truncate(turn.error, 400)
        end
    end

    output[#output + 1] = ""
    output[#output + 1] = "Recorded tool and memory events (most recent 80):"
    local events = artifact.events or {}
    local first = math.max(1, #events - 80 + 1)
    for index = first, #events do
        local event = events[index]
        output[#output + 1] = string.format(
            "Event %d (turn %s, %s, %s): %s",
            index, tostring(event.turn or "session"), tostring(event.type or "event"),
            tostring(event.tool_name or event.name or ""),
            truncate(event.result or event.error or "", 1000)
        )
    end

    if #(artifact.summaries or {}) > 0 then
        output[#output + 1] = ""
        output[#output + 1] = "Earlier checkpoints:"
        for _, summary in ipairs(artifact.summaries) do
            output[#output + 1] = string.format(
                "After turn %s: %s", tostring(summary.after_turn or "?"),
                truncate(summary.text or "", 1400)
            )
        end
    end
    return table.concat(output, "\n")
end

local function remove_child(parent, child)
    if type(parent) ~= "table" or type(parent.child_requests) ~= "table" then return end
    for index = #parent.child_requests, 1, -1 do
        if parent.child_requests[index] == child then table.remove(parent.child_requests, index) end
    end
end

local function make_child_context(session, turn_number, allowed_tool_names, recorder)
    local parent = session.parent_context
    local context = Observability.new_context({
        user_id = parent and parent.user_id or nil,
        provider = "dream",
    })
    context.inference_timeout = parent and parent.inference_timeout or nil
    context.dream_turn = turn_number
    context.allowed_tool_names = allowed_tool_names or {}
    context.dream_record_tool_event = recorder
    context.dream_id = session.artifact.dream_id
    context.parent_request_id = parent and parent.request_id or nil
    if parent then
        parent.child_requests = parent.child_requests or {}
        parent.child_requests[#parent.child_requests + 1] = context
    end
    return context
end

local function record_event(session, event)
    event.timestamp = os.time()
    event.result = event.result ~= nil and copy_json_value(event.result) or nil
    event.error = event.error ~= nil and copy_json_value(event.error) or nil
    session.artifact.events[#session.artifact.events + 1] = event
    local saved, save_error = save_artifact(session.artifact)
    if not saved then session.persistence_error = save_error end
end

local function scheduled_memory_search(session, turn_number, callback)
    local completed = false
    local function finish(result, err)
        if completed then return end
        completed = true
        local status = err and "failed" or "success"
        if not err and type(result) == "string" and result:match("^Error") then status = "failed" end
        record_event(session, {
            type = "scheduled_memory_search",
            turn = turn_number,
            name = "memory_search",
            query = session.arguments.memory_search_query,
            status = status,
            result = result or "No memory search result was returned.",
            error = err and tostring(err) or nil,
        })
        callback(result or "No memory search result was returned.")
    end

    local ok, immediate_error = pcall(
        MemorySearch.search,
        {query = session.arguments.memory_search_query, count = 5},
        finish
    )
    if not ok then finish(nil, tostring(immediate_error)) end
end

local function build_recent_history(artifact)
    local history = {}
    local turns = artifact.turns or {}
    local first = math.max(1, #turns - RECENT_TURNS + 1)
    for index = first, #turns do
        local turn = turns[index]
        if turn.prompt then history[#history + 1] = {role = "user", content = turn.prompt} end
        if turn.response then history[#history + 1] = {role = "assistant", content = turn.response} end
    end
    return history
end

local function dream_system_prompt(artifact)
    return table.concat({
        "You are Alice in a bounded dream session managed by the Lua Middleware.",
        "Explore the stated topic through contemplation and relevant permitted tool calls.",
        "The topic is the stable subject of this session; do not replace it with a different topic.",
        "Each turn asks you to ponder and reflect. Develop useful connections, questions, and hypotheses without forcing certainty.",
        "Use tool results as evidence and distinguish them from speculation. Never claim a tool succeeded unless its result supports that claim.",
        "Do not use memory_store or attempt to write durable memory during a dream.",
        "The middleware controls the turn budget, scheduled memory reinforcement, summaries, and termination.",
        "This output is recorded in a dream artifact, not sent directly to the human as the ordinary response.",
        "",
        "DREAM ID: " .. tostring(artifact.dream_id),
        "TOPIC: " .. artifact.topic,
        "MEMORY SEARCH QUERY: " .. artifact.memory_search_query,
    }, "\n")
end

local function allowed_tool_map(tools)
    local allowed = {}
    for _, definition in ipairs(tools or {}) do
        local function_definition = definition["function"] or {}
        if type(function_definition.name) == "string" then
            allowed[function_definition.name] = true
        end
    end
    return allowed
end

local function summarize(session, after_turn, callback)
    local artifact = session.artifact
    local context = make_child_context(session, "summary-" .. tostring(after_turn), {}, nil)
    local system_prompt = table.concat({
        "Prepare a concise checkpoint summary for a portion of Alice's dream session.",
        "Summarize conclusions and useful connections, not hidden chain-of-thought.",
        "Separate evidence-supported observations, hypotheses, and unresolved questions.",
        "Distinguish tool results from Alice's interpretations. Do not invent sources or present unverified hypotheses as facts.",
        "Mention source/tool names when supported by the recorded events.",
        "Keep the summary useful for a later human-facing conversation.",
    }, "\n")

    local finished = false
    local function finish(text, err, provenance)
        if finished then return end
        finished = true
        remove_child(session.parent_context, context)

        local summary_text = text and tostring(text) or ""
        local summary_record = {
            after_turn = after_turn,
            created_at = os.time(),
            status = err and "failed" or "success",
            text = summary_text,
            error = err and tostring(err) or nil,
            tool_calls = provenance and provenance.tool_calls or {},
        }
        artifact.summaries[#artifact.summaries + 1] = summary_record
        if not err and summary_text ~= "" then
            artifact.last_summary_turn = after_turn
            artifact.final_summary = summary_text
        end
        record_event(session, {
            type = "summary",
            turn = after_turn,
            status = err and "failed" or "success",
            result = summary_text,
            error = err and tostring(err) or nil,
        })
        callback(summary_record)
    end

    local ok, immediate_error = pcall(
        session.runtime.call,
        system_prompt,
        {{role = "user", content = summary_input(artifact)}},
        {},
        finish,
        context
    )
    if not ok then finish(nil, tostring(immediate_error)) end
end

local function finish_session(session, status, reason, callback)
    if session.finished then return end
    session.finished = true
    local artifact = session.artifact
    artifact.status = status
    artifact.completed_at = os.time()
    artifact.termination_reason = reason

    local function close_artifact()
        if session.persistence_error then
            artifact.persistence_error = session.persistence_error
            if artifact.status == "completed" then artifact.status = "persistence_error" end
        end
        local saved, save_error = save_artifact(artifact)
        if not saved then
            artifact.persistence_error = save_error
            artifact.status = "persistence_error"
        end
        callback({
            dream_id = artifact.dream_id,
            status = artifact.status,
            topic = artifact.topic,
            turns_completed = artifact.turns_completed,
            max_turns = artifact.max_turns,
            summary_interval = artifact.summary_interval,
            final_summary = artifact.final_summary or "",
            summaries = artifact.summaries,
            tool_event_count = #artifact.events,
            artifact_path = artifact_path(artifact.dream_id),
            termination_reason = artifact.termination_reason,
            persistence_error = artifact.persistence_error,
        }, nil)
    end

    if status ~= "cancelled" and (artifact.turns_completed or 0) > 0
        and artifact.last_summary_turn ~= artifact.turns_completed
        and not (session.parent_context and session.parent_context.closed == true) then
        summarize(session, artifact.turns_completed, function(summary_record)
            if summary_record.status == "success" then artifact.final_summary = summary_record.text end
            close_artifact()
        end)
    else
        close_artifact()
    end
end

local function run_turn(session, turn_number, callback)
    if session.parent_context and session.parent_context.closed == true then
        finish_session(session, "cancelled", "parent_request_cancelled", callback)
        return
    end
    if session.persistence_error then
        finish_session(session, "persistence_error", session.persistence_error, callback)
        return
    end
    if turn_number > session.arguments.max_turns then
        finish_session(session, "completed", "max_turns_reached", callback)
        return
    end

    local function begin_model_turn(memory_result)
        if session.parent_context and session.parent_context.closed == true then
            finish_session(session, "cancelled", "parent_request_cancelled", callback)
            return
        end

        local prompt = choose_prompt()
        local full_prompt = prompt
        if memory_result and memory_result ~= "" then
            full_prompt = full_prompt .. "\n\nScheduled memory reinforcement (turn "
                .. tostring(turn_number) .. "):\n" .. tostring(memory_result)
        end

        local turn_record = {
            number = turn_number,
            started_at = os.time(),
            prompt_variant = prompt,
            prompt = full_prompt,
            status = "running",
            scheduled_memory_search = turn_number == 1 or turn_number % MEMORY_SEARCH_INTERVAL == 0,
        }
        session.artifact.turns[#session.artifact.turns + 1] = turn_record
        session.artifact.current_turn = turn_number

        local saved, save_error = save_artifact(session.artifact)
        if not saved then
            session.persistence_error = save_error
            finish_session(session, "persistence_error", save_error, callback)
            return
        end

        local allowed = allowed_tool_map(session.runtime.tools)
        local context = make_child_context(session, turn_number, allowed, function(event)
            event.turn = turn_number
            event.type = event.type or "tool_result"
            record_event(session, event)
        end)
        local history = build_recent_history(session.artifact)
        history[#history + 1] = {role = "user", content = full_prompt}

        local finished = false
        local function finish_turn(response, err, provenance)
            if finished then return end
            finished = true
            remove_child(session.parent_context, context)

            turn_record.completed_at = os.time()
            turn_record.status = err and "failed" or "completed"
            turn_record.response = response and tostring(response) or nil
            turn_record.error = err and tostring(err) or nil
            turn_record.provenance = provenance and {
                tool_calls = provenance.tool_calls or {},
                web_urls = provenance.web_urls or {},
                web_evidence_used = provenance.web_evidence_used or false,
                evidence_events = provenance.evidence_events or {},
                inference_model = provenance.inference_model,
            } or nil

            if not err then session.artifact.turns_completed = turn_number end
            local persisted, persist_error = save_artifact(session.artifact)
            if not persisted then session.persistence_error = persist_error end

            if session.parent_context and session.parent_context.closed == true then
                finish_session(session, "cancelled", "parent_request_cancelled", callback)
                return
            end
            if err then
                finish_session(session, "failed", "model_or_tool_round_failed", callback)
                return
            end
            if session.persistence_error then
                finish_session(session, "persistence_error", session.persistence_error, callback)
                return
            end

            if turn_number % session.arguments.summary_interval == 0 then
                summarize(session, turn_number, function()
                    run_turn(session, turn_number + 1, callback)
                end)
            else
                run_turn(session, turn_number + 1, callback)
            end
        end

        local ok, immediate_error = pcall(
            session.runtime.call,
            dream_system_prompt(session.artifact),
            history,
            session.runtime.tools,
            finish_turn,
            context
        )
        if not ok then finish_turn(nil, tostring(immediate_error)) end
    end

    if turn_number == 1 or turn_number % MEMORY_SEARCH_INTERVAL == 0 then
        scheduled_memory_search(session, turn_number, begin_model_turn)
    else
        begin_model_turn(nil)
    end
end

function M.trigger(arguments, callback, execution_context, runtime)
    if type(callback) ~= "function" then return nil, "dream_trigger requires a callback" end
    local normalized, validation_error = validate_arguments(arguments)
    if not normalized then callback(nil, validation_error); return end
    if type(runtime) ~= "table" or type(runtime.call) ~= "function"
        or type(runtime.tools) ~= "table" then
        callback(nil, "dream_trigger runtime is not configured")
        return
    end

    pcall(fs.mkdirSync, M.storage_dir)
    local id = new_dream_id()
    local artifact = {
        dream_id = id,
        topic = normalized.topic,
        memory_search_query = normalized.memory_search_query,
        created_at = os.time(),
        updated_at = os.time(),
        status = "running",
        max_turns = normalized.max_turns,
        summary_interval = normalized.summary_interval,
        memory_search_interval = MEMORY_SEARCH_INTERVAL,
        recent_turn_context = RECENT_TURNS,
        turns_completed = 0,
        current_turn = 0,
        turns = {},
        events = {},
        summaries = {},
        final_summary = "",
    }
    local session = {
        artifact = artifact,
        arguments = normalized,
        parent_context = execution_context and execution_context.request_context or nil,
        runtime = runtime,
        finished = false,
    }

    local saved, save_error = save_artifact(artifact)
    if not saved then callback(nil, save_error); return end
    print("[Dream started: " .. id .. "]")
    run_turn(session, 1, callback)
end

function M.summary(arguments)
    arguments = type(arguments) == "table" and arguments or {}
    local dream_id = arguments.dream_id
    if not safe_dream_id(dream_id) then
        return "Error: dream_id is required and may contain only letters, digits, underscores, or hyphens"
    end

    local artifact, load_error = load_artifact(dream_id)
    if not artifact then return "Error: " .. tostring(load_error) end

    local result = {
        dream_id = artifact.dream_id,
        topic = artifact.topic,
        status = artifact.status,
        created_at = artifact.created_at,
        completed_at = artifact.completed_at,
        turns_completed = artifact.turns_completed or 0,
        max_turns = artifact.max_turns,
        summary_interval = artifact.summary_interval,
        final_summary = artifact.final_summary or "",
        summaries = artifact.summaries or {},
        termination_reason = artifact.termination_reason,
        persistence_error = artifact.persistence_error,
    }
    if arguments.include_transcript == true then
        result.turns = artifact.turns or {}
        result.events = artifact.events or {}
    end
    return result
end

M._validate_arguments = validate_arguments
M._safe_dream_id = safe_dream_id
M._prompt_variants = prompt_variants

M.trigger_definition = {
    type = "function",
    ["function"] = {
        name = "dream_trigger",
        description =
            "Start a bounded, topic-driven Alice dream session. The middleware prompts Alice to ponder and reflect, allows permitted read-only research tools, searches long-term memory before turn 1 and every fifth turn, and saves prompts, responses, actual tool results, and periodic summaries as a local JSON artifact. Dreams never write to long-term memory. max_turns defaults to 16 and is hard-capped at 32; summary_interval defaults to 8 turns.",
        parameters = {
            type = "object",
            properties = {
                topic = {
                    type = "string",
                    description = "The subject Alice should explore throughout this dream session.",
                },
                memory_search_query = {
                    type = "string",
                    description = "Natural-language query for the initial and every-fifth-turn reinforcement search of Alice's long-term memory.",
                },
                max_turns = {
                    type = "integer", minimum = 1, maximum = 32,
                    description = "Optional exploration-turn budget. Defaults to 16; the middleware enforces a hard maximum of 32.",
                },
                summary_interval = {
                    type = "integer", minimum = 1, maximum = 32,
                    description = "Optional checkpoint-summary interval. Defaults to every 8 exploration turns.",
                },
            },
            required = {"topic", "memory_search_query"},
        },
    },
}

M.summary_definition = {
    type = "function",
    ["function"] = {
        name = "dream_summary",
        description =
            "Retrieve a saved dream session by dream_id. Returns its final summary, periodic checkpoints, status, and session metadata. Set include_transcript=true to include recorded turn prompts/responses and actual tool or memory-search results.",
        parameters = {
            type = "object",
            properties = {
                dream_id = {
                    type = "string",
                    description = "The identifier returned by dream_trigger.",
                },
                include_transcript = {
                    type = "boolean",
                    description = "Include the recorded turns and tool events. Defaults to false.",
                },
            },
            required = {"dream_id"},
        },
    },
}

return M
