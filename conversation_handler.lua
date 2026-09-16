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

-- conversation_handler.lua
-- Pattern matching, handler detection, and explicit handler selection.
-- Lua 5.1 compatible.

local ConversationHandler = {}

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

local reset_keywords = {
"reset",
"%[RESET%]",
"/reset",
}

function ConversationHandler.normalize_input(user_input)
return tostring(user_input or "")
:lower()
:match("^%s*(.-)%s*$")
end

function ConversationHandler.match_handler_pattern(
handler_name,
normalized_input
)
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

function ConversationHandler.is_reset(normalized_input)
for _, keyword in ipairs(reset_keywords) do
if normalized_input:match(keyword) then
return true
end
end


return false


end

function ConversationHandler.detect_handler(user_input)
local normalized =
ConversationHandler.normalize_input(user_input)


if ConversationHandler.is_reset(normalized) then
    return {
        type = "reset"
    }
end

for handler_name, _ in pairs(handlers) do
    local claim =
        ConversationHandler.match_handler_pattern(
            handler_name,
            normalized
        )

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

function ConversationHandler.get_handler(handler_name)
local handler = handlers[handler_name]


if not handler or not handler.enabled then
    return nil
end

return handler


end

function ConversationHandler.build_override_prompt(
handler_name,
claim
)
local handler =
ConversationHandler.get_handler(handler_name)


if not handler then
    return ""
end

return string.format(
    handler.override_template,
    tostring(claim or "")
)


end

-- Build an override directly from a frontend checkbox.

-- This intentionally does not alter the existing pattern matcher.
function ConversationHandler.build_selected_override(
handler_name
)
local handler =
ConversationHandler.get_handler(handler_name)


if not handler then
    return nil
end

local template = handler.override_template

-- Gaslighting's normal template expects a captured claim.
-- Checkbox activation has no claim, so provide a neutral
-- description instead of passing nil to string.format().
if handler_name == "gaslighting" then
    return string.format(
        template,
        "the current conversation context"
    )
end

return template


end

function ConversationHandler.display_history(history)
if #history == 0 then
print("\n[No conversation history]\n")
return
end


print("\n--- Conversation History ---")

for i, msg in ipairs(history) do
    local role =
        tostring(msg.role or ""):upper()

    local handler_note = ""

    if msg.handler_applied then
        handler_note =
            string.format(
                " [%s]",
                msg.handler_applied
            )
    end

    print(string.format(
        "%d. [%s]%s:\n %s\n",
        i,
        role,
        handler_note,
        tostring(msg.content or "")
    ))
end

print("--- End History ---\n")


end

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
