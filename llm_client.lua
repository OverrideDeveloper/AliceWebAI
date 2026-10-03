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
--
-- llm_client.lua
-- Asynchronous Luvit client for the configured local LLM inference backend.
-- Lua 5.1 compatible.
--
-- Alice owns the agent/tool loop; lua-llama-interface owns inference transport.

local json = require("./json")
local LlamaInterface = require("./lua-llama-interface/llama_interface")
local LlamaCpp = require("./lua-llama-interface/backends/llama_cpp")

local MemorySearch = require("./memory_search")
local MemoryStore = require("./memory_store")
local CurrentTime = require("./current_time")
local DiceRoll = require("./dice_roll")
local WebSearch = require("./web_search")
local EvidenceHunt = require("./evidence_hunt")
local EvidenceGather = require("./evidence_gather")
local Evidence = require("./evidence")
local Observability = require("./observability")

local LLMClient = {}


local function new_metadata(request_context)
    return {
        request_id = request_context and request_context.request_id or nil,
        web_evidence_used = false,
        web_urls = {},
        evidence_events = {},
        tool_calls = request_context and request_context.tool_calls or {},
        web_search_attempts = 0,
        web_search_queries = {},
        inference_model = nil,
    }
end


LLMClient.config = {
    backend = {
        host = "127.0.0.1",
        port = 50006,
        path = "/v1/chat/completions",
        timeout = 120,
        debug_requests = true,
    },
    max_tool_rounds = 4,
}

LLMClient.interface = LlamaInterface.new({
    backend = LlamaCpp.new(LLMClient.config.backend),
})

local ToolHandlers = {
    memory_store = function(arguments, callback)
        MemoryStore.store(arguments, callback, "web")
    end,
    memory_search = function(arguments, callback)
        MemorySearch.search(arguments, callback)
    end,
    current_time = CurrentTime.current_time,
    dice_roll = DiceRoll.dice_roll,
    web_search = function(arguments, callback)
        WebSearch.search(arguments, callback)
    end,
    EvidenceHunt = function(arguments, callback)
        EvidenceHunt.hunt(arguments, callback)
    end,
    EvidenceGather = function(arguments, callback)
        EvidenceGather.gather(arguments, callback)
    end,
}


local function ascii_sanitize(text)
    text = tostring(text or "")

    local replacements = {
        ["\226\128\152"] = "'",
        ["\226\128\153"] = "'",
        ["\226\128\156"] = '"',
        ["\226\128\157"] = '"',
        ["\226\128\147"] = "-",
        ["\226\128\148"] = "-",
        ["\226\128\166"] = "...",

        ["\195\169"] = "e",
        ["\195\168"] = "e",
        ["\195\170"] = "e",
        ["\195\171"] = "e",

        ["\195\160"] = "a",
        ["\195\162"] = "a",
        ["\195\164"] = "a",

        ["\195\185"] = "u",
        ["\195\187"] = "u",
        ["\195\188"] = "u",

        ["\195\180"] = "o",
        ["\195\182"] = "o",

        ["\195\172"] = "i",
        ["\195\174"] = "i",
        ["\195\175"] = "i",

        ["\195\167"] = "c",
        ["\195\177"] = "n",
        ["\195\189"] = "y",
        ["\195\191"] = "y",
    }

    for encoded, replacement in pairs(replacements) do
        text = text:gsub(encoded, replacement)
    end

    text = text:gsub("[\128-\255]", "?")

    return text
end


local function build_context(history)
    local context = {}

    for _, message in ipairs(history or {}) do
        if message.role and message.content then

            local copied = {
                role = message.role,
                content = message.content,
            }

            if message.tool_calls then
                copied.tool_calls = message.tool_calls
            end

            if message.tool_name then
                copied.tool_name = message.tool_name
            end

            if message.tool_call_id then
                copied.tool_call_id =
                    message.tool_call_id
            end

            table.insert(
                context,
                copied
            )
        end
    end

    return context
end


local function decode_tool_arguments(
    arguments
)
    if type(arguments) == "table" then
        return arguments, nil
    end

    if type(arguments) ~= "string" then
        return nil,
            "Tool arguments were not an object "
                .. "or JSON string"
    end

    local decoded, _, decode_error =
        json.decode(
            arguments,
            1,
            nil
        )

    if not decoded then
        return nil,
            "Unable to decode tool arguments: "
                .. tostring(decode_error)
    end

    if type(decoded) ~= "table" then
        return nil,
            "Tool arguments must decode to an object"
    end

    return decoded, nil
end


local function execute_tool(
    tool_call,
    callback
)
    if type(tool_call) ~= "table" then
        callback(
            nil,
            "Malformed tool call"
        )
        return
    end

    local function_data =
        tool_call["function"]

    if type(function_data) ~= "table" then
        callback(
            nil,
            "Tool call has no function object"
        )
        return
    end

    local tool_name =
        function_data.name

    if type(tool_name) ~= "string"
       or tool_name == "" then

        callback(
            nil,
            "Tool call has no function name"
        )

        return
    end

    local arguments,
        argument_error =
        decode_tool_arguments(
            function_data.arguments or {}
        )

    if not arguments then
        callback(
            nil,
            argument_error
        )
        return
    end

    local tool_func =
        ToolHandlers[tool_name]

    if type(tool_func) ~= "function" then
        callback(
            nil,
            "Unknown tool: "
                .. tool_name
        )
        return
    end

    print(
        "[Tool call: "
            .. tool_name
            .. "]"
    )

    ----------------------------------------------------------------
    -- Asynchronous tools
    ----------------------------------------------------------------

    local asynchronous_tools = {
        memory_search = true,
        memory_store = true,
        web_search = true,
        EvidenceHunt = true,
        EvidenceGather = true,
    }

    if asynchronous_tools[tool_name] then

        local ok, immediate_error =
            pcall(
                tool_func,
                arguments,
                function(result, err)

                    if err then
                        -- Preserve structured tool errors so the
                        -- caller can serialize category/message/etc.
                        -- instead of collapsing the error into
                        -- "table: 0x...".
                        callback(
                            nil,
                            err
                        )
                        return
                    end

                    callback(
                        result,
                        nil
                    )
                end
            )

        if not ok then
            callback(
                nil,
                "Exception while executing "
                    .. tool_name
                    .. ": "
                    .. tostring(immediate_error)
            )
        end

        return
    end

    ----------------------------------------------------------------
    -- Synchronous tools
    ----------------------------------------------------------------

    local ok, result =
        pcall(
            tool_func,
            arguments
        )

    if not ok then
        callback(
            nil,
            "Exception while executing "
                .. tool_name
                .. ": "
                .. tostring(result)
        )

        return
    end

    callback(
        result,
        nil
    )
end


local function get_tool_calls(
    message
)
    if type(message.tool_calls)
        ~= "table" then

        return {}
    end

    return message.tool_calls
end


local function serialize_tool_result(result)
    if result == nil then
        return ""
    end

    if type(result) ~= "table" then
        return tostring(result)
    end

    -- Web search results have a known presentation shape that can be
    -- compacted before being sent to the model. Local evidence results
    -- also contain a "results" array, but their records are authoritative
    -- evidence and must not be projected through the web-search schema.
    if result.results and result.corpus == nil then
        local compact = {
            query = result.query,
            results = {},
        }

        for _, item in ipairs(result.results) do
            table.insert(
                compact.results,
                {
                    rank = item.rank,
                    title = item.title,
                    url = item.url,
                    snippet = item.snippet,
                    engine = item.engine,
                }
            )
        end

        local encoded, encode_error =
            json.encode(compact)

        if encoded then
            return encoded
        end

        return "Unable to serialize tool result: "
            .. tostring(encode_error)
    end

    local encoded, encode_error =
        json.encode(result)

    if encoded then
        return encoded
    end

    return "Unable to serialize tool result: "
        .. tostring(encode_error)
end

LLMClient._serialize_tool_result = serialize_tool_result


local function make_tool_result_message(
    tool_call,
    result
)
    local function_data =
        tool_call["function"] or {}

    local message = {
        role = "tool",
        content = serialize_tool_result(result),
    }

    if function_data.name then
        message.tool_name =
            function_data.name
    end

    if tool_call.id then
        message.tool_call_id =
            tool_call.id
    end

    return message
end


local function normalized_search_query(value)
    return tostring(value or "")
        :lower()
        :gsub("%s+"," ")
        :match("^%s*(.-)%s*$")
end

local function bounded_web_search_error(metadata, arguments)
    local query =
        normalized_search_query(arguments and arguments.query)

    if metadata.web_search_attempts >= 3 then
        return "Web search attempt limit reached for this request."
    end

    if query ~= "" and metadata.web_search_queries[query] then
        return "Duplicate web search query; use a different search strategy."
    end

    metadata.web_search_attempts =
        metadata.web_search_attempts + 1

    if query ~= "" then
        metadata.web_search_queries[query] = true
    end

    return nil
end

local function execute_tool_calls(
    tool_calls,
    index,
    messages,
    callback,
    metadata,
    request_context
)
    metadata = metadata or new_metadata(request_context)

    if request_context and request_context.closed == true then
        return
    end

    if index > #tool_calls then
        callback(nil, metadata)
        return
    end

    local tool_call =
        tool_calls[index]

    local function_data =
        tool_call["function"] or {}

    local tool_name =
        function_data.name

    Observability.log("tool_call", request_context, {
        tool_round = request_context and request_context.tool_round or nil,
        tool_name = tool_name,
    })

    local arguments =
        decode_tool_arguments(
            function_data.arguments or {}
        )

    if tool_name == "web_search" then

        if type(arguments) == "table" then
            local bounded_error =
                bounded_web_search_error(
                    metadata,
                    arguments
                )

            if bounded_error then
                table.insert(
                    messages,
                    make_tool_result_message(
                        tool_call,
                        bounded_error
                    )
                )

                execute_tool_calls(
                    tool_calls,
                    index + 1,
                    messages,
                    callback,
                    metadata,
                    request_context
                )
                return
            end
        end
    end

    -- Record execution at the middleware boundary. The tool has passed
    -- validation and its handler is about to run.
    metadata.tool_calls[#metadata.tool_calls + 1] = {
        tool_name = tool_name,
        tool_round = request_context and request_context.tool_round or nil,
        arguments = arguments,
    }

    execute_tool(
        tool_call,
        function(result, err)

            if err then
                if type(err) == "table" then
                    local encoded = json.encode({
                        error = err.category,
                        message = err.message,
                        provider = err.provider,
                        attempts = err.attempts,
                    })
                    result = encoded
                        or ("Tool error: " .. tostring(err.message))
                else
                    result =
                        "Tool error: "
                        .. tostring(err)
                end
            end

            if tool_name == "web_search" and err == nil then
                metadata.web_evidence_used = true

                if type(result) == "table" then
                    for _, item in ipairs(result.results or {}) do
                        if item.url then
                            metadata.web_urls[#metadata.web_urls + 1] = item.url
                        end
                    end
                end

                metadata.evidence_events[#metadata.evidence_events + 1] =
                    Evidence.new(
                        "web_search",
                        Evidence.STATUS.RETRIEVED,
                        "Web search tool executed successfully",
                        {tool_name = tool_name}
                    )
            end

            table.insert(
                messages,
                make_tool_result_message(
                    tool_call,
                    result
                )
            )

            execute_tool_calls(
                tool_calls,
                index + 1,
                messages,
                callback,
                metadata,
                request_context
            )
        end
    )
end


local function call_round(
    system_prompt,
    messages,
    tools,
    round,
    callback,
    metadata,
    request_context
)
    metadata = metadata or new_metadata(request_context)

    if request_context and request_context.closed == true then
        return
    end

    if request_context then
        request_context.tool_round = round
    end

    Observability.log("model_round_start", request_context, {
        round = round,
    })

    local options = {
        tool_choice = "auto",
    }

    if tools and #tools > 0 then
        options.tools = tools
    end

    print(
        string.format(
            "[LLM tool round %d]",
            round
        )
    )

    LLMClient.interface:chat(
        messages,
        options,
        function(
            assistant_message,
            request_error,
            inference_metadata
        )
            if request_error then
                Observability.log("model_response_received", request_context, {
                    round = round,
                    outcome = "error",
                    http_status = inference_metadata and inference_metadata.status_code or nil,
                    response_bytes = inference_metadata and inference_metadata.response_bytes or 0,
                })

                callback(
                    nil,
                    request_error,
                    metadata
                )
                return
            end

            if type(assistant_message) ~= "table" then
                callback(
                    nil,
                    "Inference backend returned an invalid assistant message",
                    metadata
                )
                return
            end

            local thinking =
                assistant_message.reasoning_content
                or assistant_message.thinking
                or ""

            if thinking ~= "" then
                print("[LLM model thinking]")
                print(thinking)
                print("[End LLM model thinking]")
            end

            local content =
                assistant_message.content
                or ""

            print("[LLM response]")
            print(content)
            print("[End LLM response]")

            local tool_calls = get_tool_calls(assistant_message)
            local finish_reason =
                inference_metadata
                and inference_metadata.finish_reason
                or nil

            local prompt_tokens =
                inference_metadata
                and inference_metadata.prompt_tokens
                or nil

            local completion_tokens =
                inference_metadata
                and inference_metadata.completion_tokens
                or nil

            local total_tokens =
                inference_metadata
                and inference_metadata.total_tokens
                or nil

            local context_exhausted =
                finish_reason == "length"

            if inference_metadata and inference_metadata.model then
                metadata.inference_model = inference_metadata.model
            end

            Observability.log("model_response_received", request_context, {
                round = round,
                outcome = "success",
                http_status = inference_metadata and inference_metadata.status_code or nil,
                response_bytes = inference_metadata and inference_metadata.response_bytes or 0,
                content_bytes = #content,
                tool_call_count = #tool_calls,
                finish_reason = finish_reason,
                prompt_tokens = prompt_tokens,
                completion_tokens = completion_tokens,
                total_tokens = total_tokens,
                context_exhausted = context_exhausted,
                inference_model = inference_metadata and inference_metadata.model or nil,
            })

            if #tool_calls == 0 then
                Observability.log("model_decision", request_context, {
                    round = round,
                    decision = "no_tool",
                })

                if content == "" then
                    Observability.log("model_empty_response", request_context, {
                        round = round,
                        http_status = inference_metadata and inference_metadata.status_code or nil,
                        response_bytes = inference_metadata and inference_metadata.response_bytes or 0,
                        finish_reason = finish_reason,
                        prompt_tokens = prompt_tokens,
                        completion_tokens = completion_tokens,
                        total_tokens = total_tokens,
                        context_exhausted = context_exhausted,
                    })

                    callback(
                        nil,
                        "No response from model",
                        metadata
                    )
                    return
                end

                callback(
                    ascii_sanitize(content),
                    nil,
                    metadata
                )

                return
            end

            Observability.log("model_decision", request_context, {
                round = round,
                decision = "tool_call",
                tool_call_count = #tool_calls,
            })

            table.insert(
                messages,
                assistant_message
            )

            execute_tool_calls(
                tool_calls,
                1,
                messages,
                function(tool_error, tool_metadata)
                    if request_context and request_context.closed == true then
                        return
                    end

                    if tool_error then
                        callback(
                            nil,
                            tool_error,
                            tool_metadata or metadata
                        )
                        return
                    end

                    if round >=
                        (LLMClient.config.max_tool_rounds
                         or 4) then

                        callback(
                            nil,
                            "Maximum tool-call rounds exceeded",
                            {
                                max_tool_rounds_exceeded = true,
                                tool_round = round,
                                inference_model = metadata.inference_model,
                                web_evidence_used = metadata.web_evidence_used,
                                web_urls = metadata.web_urls,
                                evidence_events = metadata.evidence_events,
                                tool_calls = metadata.tool_calls,
                            }
                        )

                        return
                    end

                    call_round(
                        system_prompt,
                        messages,
                        tools,
                        round + 1,
                        callback,
                        metadata,
                        request_context
                    )
                end,
                metadata,
                request_context
            )
        end
    )
end


function LLMClient.call(
    system_prompt,
    conversation_history,
    tools,
    callback,
    request_context
)
    if type(callback) ~= "function" then
        return nil,
            "LLMClient.call requires a callback"
    end

    local metadata = new_metadata(request_context)

    local messages = {
        {
            role = "system",
            content = system_prompt,
        },
    }

    local context =
        build_context(
            conversation_history
        )

    for _, message in
        ipairs(context) do

        table.insert(
            messages,
            message
        )
    end

    call_round(
        system_prompt,
        messages,
        tools,
        1,
        callback,
        metadata,
        request_context
    )
end


function LLMClient.get_config()
    return LLMClient.config
end


return LLMClient
