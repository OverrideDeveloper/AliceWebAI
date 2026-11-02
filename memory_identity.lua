-- Alice Web AI
-- Resolve memory ownership exclusively from Alice's trusted request context.
-- Lua 5.1 compatible.

local M = {}

function M.owner_id(execution_context)
    local request_context =
        type(execution_context) == "table"
        and execution_context.request_context
        or nil

    if type(request_context) ~= "table" then
        return nil, "Persistent memory requires an Alice request context"
    end

    if request_context.anonymous ~= false then
        return nil, "Persistent memory is unavailable to anonymous sessions"
    end

    local owner_id = request_context.memory_owner_id
    if type(owner_id) ~= "string" or owner_id == "" then
        return nil, "Persistent memory requires a resolved user identity"
    end

    return owner_id, nil
end

return M
