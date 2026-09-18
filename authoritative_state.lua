-- Alice Web AI
-- Generic authoritative state container for stateful workflows.
-- Lua 5.1 compatible.

local Policy = require("./policy")

local M = {}

function M.new(initial_state)
    local state = initial_state or {}

    return {
        state = state,
        version = 0,
    }
end

function M.get(container, key)
    if not container or not container.state then
        return nil
    end

    return container.state[key]
end

function M.set(container, key, value)
    container.state[key] = value
    container.version = container.version + 1
end

function M.record_human_action(container, action)
    local ok, err = Policy.assert_human_action(action)

    if not ok then
        return false, err
    end

    container.state.last_human_action = action
    container.state.requires_human_action = false
    container.version = container.version + 1

    return true, nil
end

function M.require_human_action(container, reason)
    container.state.requires_human_action = true
    container.state.pending_human_action = reason
    container.version = container.version + 1
end

function M.advance(container, next_state, action)
    local ok, err =
        Policy.can_advance_state(container.state, action)

    if not ok then
        return false, err
    end

    container.state.phase = next_state
    container.state.pending_human_action = nil
    container.version = container.version + 1

    return true, nil
end

function M.snapshot(container)
    local result = {
        version = container.version,
        state = {},
    }

    for key, value in pairs(container.state) do
        result.state[key] = value
    end

    return result
end

return M
