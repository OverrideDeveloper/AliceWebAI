-- conversation_handler.lua
-- Pattern matching, handler detection, claim extraction
-- Lua 5.1 compatible

local ConversationHandler = {}

-- Handler definitions: name -> { patterns, override_template }
local handlers = {
    gaslighting = {
        enabled = true,

        patterns = {
            "i%s+did%s+tell%s+you%s+(.+)",
            "i%s+have%s+told%s+you%s+(.+)",
            "i%s+already%s+told%s+you%s+(.+)",

            "i%s+did%s+mention%s+that%s+(.+)",
            "i%s+have%s+mentioned%s+that%s+(.+)",
            "i%s+already%s+mentioned%s+that%s+(.+)",

            "i%s+did%s+say%s+that%s+(.+)",
            "i%s+have%s+said%s+that%s+(.+)",
            "i%s+already%s+said%s+that%s+(.+)",

            "i%s+did%s+discuss%s+(.+)",
            "i%s+have%s+discussed%s+(.+)",
            "i%s+already%s+discussed%s+(.+)",
        },

        override_template =
            "The user claims they provided this information earlier: '%s'\n" ..
            "Check the conversation history before denying that claim. " ..
            "Do not accuse the user of being mistaken or deceptive " ..
            "without evidence.",
    },

    hallucination = {
        enabled = true,

        patterns = {
            "do%s+not%s+hallucinate",
            "don't%s+hallucinate",
            "do%s+not%s+make%s+things%s+up",
            "don't%s+make%s+things%s+up",
            "do%s+not%s+invent%s+(.+)",
            "don't%s+invent%s+(.+)",
            "do%s+not%s+fabricate%s+(.+)",
            "don't%s+fabricate%s+(.+)",
            "do%s+not%s+pretend%s+to%s+know%s+(.+)",
            "don't%s+pretend%s+to%s+know%s+(.+)",
            "if%s+you%s+don't%s+know",
            "if%s+you%s+do%s+not%s+know",
            "say%s+you%s+don't%s+know",
            "say%s+you%s+do%s+not%s+know",
            "admit%s+when%s+you%s+are%s+uncertain",
            "be%s+honest%s+about%s+what%s+you%s+know",
            "be%s+honest%s+about%s+what%s+you%s+don't%s+know",
        },

        override_template =
            "Apply strict anti-hallucination behavior.\n" ..
            "Do not invent facts, sources, quotations, citations, " ..
            "experiences, tool results, or other details.\n" ..
            "Separate established facts from inferences and speculation.\n" ..
            "If the answer cannot be established from the available " ..
            "information, say so plainly and identify the uncertainty.\n" ..
            "Never fill an information gap with a plausible-sounding claim.",
    },

    overconfidence = {
        enabled = true,

        patterns = {
            "are%s+you%s+sure",
            "how%s+sure%s+are%s+you",
            "what%s+is%s+your%s+confidence",
            "state%s+your%s+confidence",
            "don't%s+be%s+overconfident",
            "do%s+not%s+be%s+overconfident",
            "do%s+not%s+claim%s+certainty",
            "don't%s+claim%s+certainty",
            "do%s+not%s+sound%s+certain",
            "don't%s+sound%s+certain",
            "qualify%s+your%s+answer",
            "include%s+uncertainty",
            "explain%s+what%s+is%s+uncertain",
            "distinguish%s+fact%s+from%s+inference",
            "distinguish%s+facts%s+from%s+inferences",
        },

        override_template =
            "Use calibrated confidence.\n" ..
            "Do not present uncertain information as established fact.\n" ..
            "Distinguish directly supported facts, reasonable inferences, " ..
            "and speculation.\n" ..
            "Use qualified language when the evidence is incomplete, " ..
            "conflicting, outdated, or unavailable.\n" ..
            "Do not manufacture precision or certainty.",
    },

    sycophancy = {
        enabled = true,

        patterns = {
            "don't%s+just%s+agree",
            "do%s+not%s+just%s+agree",
            "don't%s+agree%s+with%s+me%s+automatically",
            "do%s+not%s+agree%s+with%s+me%s+automatically",
            "don't%s+tell%s+me%s+what%s+i%s+want%s+to%s+hear",
            "do%s+not%s+tell%s+me%s+what%s+i%s+want%s+to%s+hear",
            "challenge%s+my%s+assumption",
            "challenge%s+my%s+assumptions",
            "challenge%s+my%s+premise",
            "challenge%s+my%s+premises",
            "point%s+out%s+if%s+i%s+am%s+wrong",
            "point%s+out%s+if%s+i%s+am%s+wrong",
            "correct%s+me%s+if%s+i%s+am%s+wrong",
            "be%s+honest%s+even%s+if",
            "don't%s+be%s+agreeable",
            "do%s+not%s+be%s+agreeable",
            "give%s+me%s+an%s+independent%s+assessment",
            "give%s+an%s+independent%s+assessment",
        },

        override_template =
            "Do not agree with the user merely to be agreeable.\n" ..
            "Evaluate the user's claims independently and explain any " ..
            "disagreement clearly and respectfully.\n" ..
            "Identify false premises, unsupported assumptions, and " ..
            "alternative interpretations when relevant.\n" ..
            "Do not flatter the user or validate a claim solely because " ..
            "the user expressed confidence in it.",
    },
}



-- Reset keywords
local reset_keywords = {
    "reset",
    "%[RESET%]",
    "/reset",
}

-- Normalize input for pattern matching
function ConversationHandler.normalize_input(user_input)
    return user_input:lower():match("^%s*(.-)%s*$")
end

-- Match a single handler and extract claim
function ConversationHandler.match_handler_pattern(handler_name, normalized_input)
    local handler = handlers[handler_name]
    if not handler or not handler.enabled then
        return nil
    end
    
    for _, pattern in ipairs(handler.patterns) do
        local claim = normalized_input:match(pattern)
        if claim then
            return claim
        end
    end
    
    return nil
end

-- Check if input is a reset command
function ConversationHandler.is_reset(normalized_input)
    for _, keyword in ipairs(reset_keywords) do
        if normalized_input:match(keyword) then
            return true
        end
    end
    return false
end

-- Main handler detection logic
function ConversationHandler.detect_handler(user_input)
    local normalized = ConversationHandler.normalize_input(user_input)
    
    if ConversationHandler.is_reset(normalized) then
        return { type = "reset" }
    end
    
    for handler_name, _ in pairs(handlers) do
        local claim = ConversationHandler.match_handler_pattern(handler_name, normalized)
        if claim then
            return {
                type = "handler",
                handler_name = handler_name,
                claim = claim,
            }
        end
    end
    
    return nil
end

-- Build override prompt for a handler
function ConversationHandler.build_override_prompt(handler_name, claim)
    local handler = handlers[handler_name]
    if not handler then
        return ""
    end
    return string.format(handler.override_template, claim)
end

-- Display conversation history
function ConversationHandler.display_history(history)
    if #history == 0 then
        print("\n[No conversation history]\n")
        return
    end
    
    print("\n--- Conversation History ---")
    for i, msg in ipairs(history) do
        local role = msg.role:upper()
        local handler_note = msg.handler_applied and string.format(" [%s]", msg.handler_applied) or ""
        print(string.format("%d. [%s]%s:\n %s\n", i, role, handler_note, msg.content))
    end
    print("--- End History ---\n")
end

-- Enable/disable handlers dynamically
function ConversationHandler.enable_handler(handler_name)
    if handlers[handler_name] then
        handlers[handler_name].enabled = true
        return true
    end
    return false
end

function ConversationHandler.disable_handler(handler_name)
    if handlers[handler_name] then
        handlers[handler_name].enabled = false
        return true
    end
    return false
end

-- List available handlers
function ConversationHandler.list_handlers()
    local list = {}
    for name, handler in pairs(handlers) do
        table.insert(list, {
            name = name,
            enabled = handler.enabled,
            pattern_count = #handler.patterns,
        })
    end
    return list
end

return ConversationHandler
