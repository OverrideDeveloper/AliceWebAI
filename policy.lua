-- Alice Web AI
-- Capability and human-agency policy primitives.
-- Lua 5.1 compatible.

local M = {}

local allowed_tools = {
    memory_search = true,
    memory_store = true,
    current_time = true,
    dice_roll = true,
    web_search = true,
}

function M.identity_status(identity)
    identity = identity or {}

    if identity.verified == true then
        return "verified"
    end

    if identity.authenticated == true then
        return "asserted"
    end

    return "anonymous"
end

function M.can_use_tool(identity, tool_name)
    if not allowed_tools[tool_name] then
        return false, "Tool is not allowlisted: " .. tostring(tool_name)
    end

    -- Web search is intentionally available to anonymous users.
    -- Access control belongs to the tool policy, not the model.
    if tool_name == "web_search" then
        return true, nil
    end

    return true, nil
end

function M.tool_is_allowlisted(tool_name)
    return allowed_tools[tool_name] == true
end

-- A stateful workflow may only cross a human decision point after an
-- explicit human action has been recorded.
function M.can_advance_state(state, action)
    state = state or {}

    if state.requires_human_action == true then
        if type(action) ~= "table" or
           action.actor_type ~= "human" or
           action.action == nil then
            return false,
                "Human decision is required before this state can advance"
        end
    end

    return true, nil
end

function M.assert_human_action(action)
    if type(action) ~= "table" or
       action.actor_type ~= "human" or
       action.action == nil then
        return false,
            "State-changing action must be explicitly attributed to a human"
    end

    return true, nil
end

function M.should_store_memory(arguments)
    arguments = arguments or {}

    return arguments.user_requested == true
        or arguments.durable == true
end

return M
