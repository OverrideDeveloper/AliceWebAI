-- Alice Web AI
-- Shared in-memory registry for model-facing tool definitions.
-- Lua 5.1 / Luvit compatible.

local M = {}

local entries = {}
local ordered_names = {}
local initialized = false

-- These tools must remain available and cannot be unloaded.
local protected_from_unload = {
    discover_tool = true,
    memory_search = true,
    memory_store = true,
    vm_execute = true,
}

local function get_name(definition)
    if type(definition) ~= "table"
        or type(definition["function"]) ~= "table" then
        return nil
    end

    local name = definition["function"].name
    if type(name) ~= "string" or name == "" then
        return nil
    end

    return name
end

function M.initialize(definitions, synopses, initially_loaded)
    if initialized then
        return true
    end

    synopses = synopses or {}
    initially_loaded = initially_loaded or {}

    for _, definition in ipairs(definitions or {}) do
        local name = get_name(definition)
        if not name then
            return nil, "Tool registry received a definition without a function name"
        end

        if entries[name] then
            return nil, "Duplicate tool registered: " .. name
        end

        entries[name] = {
            tool_name = name,
            description = definition,
            synopsis = synopses[name]
                or definition["function"].description
                or ("Registered tool " .. name .. "."),
            loaded = initially_loaded[name] == true,
        }
        ordered_names[#ordered_names + 1] = name
    end

    initialized = true
    return true
end

function M.is_initialized()
    return initialized
end

function M.get(tool_name)
    return entries[tool_name]
end

function M.is_loaded(tool_name)
    local entry = entries[tool_name]
    return entry ~= nil and entry.loaded == true
end

function M.list()
    local result = {}

    for _, name in ipairs(ordered_names) do
        local entry = entries[name]
        result[#result + 1] = {
            tool_name = entry.tool_name,
            synopsis = entry.synopsis,
            loaded = entry.loaded,
        }
    end

    return result
end

function M.get_definitions()
    local result = {}

    for _, name in ipairs(ordered_names) do
        result[#result + 1] = entries[name].description
    end

    return result
end

-- Preserve the caller's tool surface (for example, the restricted dream
-- surface) while reflecting the registry's live loaded state each round.
function M.filter_loaded(definitions)
    local result = {}

    for _, definition in ipairs(definitions or {}) do
        local name = get_name(definition)
        if name and M.is_loaded(name) then
            result[#result + 1] = entries[name].description
        end
    end

    return result
end

function M.load(tool_name)
    local entry = entries[tool_name]
    if not entry then
        return nil, "Unknown tool: " .. tostring(tool_name)
    end

    local changed = not entry.loaded
    entry.loaded = true

    return {
        tool_name = entry.tool_name,
        synopsis = entry.synopsis,
        loaded = true,
        changed = changed,
    }
end

function M.unload(tool_name)
    local entry = entries[tool_name]
    if not entry then
        return nil, "Unknown tool: " .. tostring(tool_name)
    end

    if protected_from_unload[tool_name] then
        return nil, "Tool is protected from unloading: " .. tool_name
    end

    local changed = entry.loaded
    entry.loaded = false

    return {
        tool_name = entry.tool_name,
        synopsis = entry.synopsis,
        loaded = false,
        changed = changed,
    }
end

return M
