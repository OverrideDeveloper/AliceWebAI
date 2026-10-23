-- Alice Web AI
-- Regression tests for batched discover_tool loading.
-- Lua 5.1 / Luvit compatible.

local ToolRegistry = require("../tool_registry")
local DiscoverTool = require("../discover_tool")

local function definition(name, description)
    return {
        type = "function",
        ["function"] = {
            name = name,
            description = description,
            parameters = {type = "object", properties = {}},
        },
    }
end

assert(ToolRegistry.initialize({
    definition("discover_tool", "Manage tools."),
    definition("memory_search", "Search memories."),
    definition("current_time", "Get current time."),
    definition("local_weather", "Get local weather."),
}, {
    discover_tool = "Manage tools.",
    memory_search = "Search memories.",
    current_time = "Get current time.",
    local_weather = "Get local weather.",
}, {
    discover_tool = true,
    memory_search = true,
}), "Registry initialization should succeed")

local loaded = DiscoverTool.discover({
    mode = "load_tool",
    tool_names = {"current_time", "local_weather"},
})

assert(loaded, "Batch load should return a result")
assert(loaded.loaded_count == 2, "Both requested tools should load")
assert(loaded.failed_count == 0, "Valid batch should have no failures")
assert(#loaded.results == 2, "Each requested tool should have a result")
assert(ToolRegistry.is_loaded("current_time"), "current_time should be loaded")
assert(ToolRegistry.is_loaded("local_weather"), "local_weather should be loaded")

assert(type(loaded.registry) == "table", "Load result should include registry state")
local registry_by_name = {}
for _, entry in ipairs(loaded.registry) do
    assert(entry.tool_name ~= nil, "Registry entry should include tool_name")
    assert(entry.synopsis ~= nil, "Registry entry should include synopsis")
    assert(type(entry.loaded) == "boolean", "Registry entry should include loaded state")
    local property_count = 0
    for _ in pairs(entry) do
        property_count = property_count + 1
    end
    assert(property_count == 3, "Registry entries should contain exactly three properties")
    registry_by_name[entry.tool_name] = entry
end
assert(registry_by_name.current_time.loaded == true)
assert(registry_by_name.local_weather.loaded == true)
assert(registry_by_name.memory_search.loaded == true)

local mixed = DiscoverTool.discover({
    mode = "load_tool",
    tool_names = {"hn_top_news", "deck_draw"},
})
assert(mixed, "Batch load with unknown names should return per-tool results")
assert(mixed.loaded_count == 0)
assert(mixed.failed_count == 2)
assert(#mixed.results == 2)
assert(mixed.results[1].error ~= nil)
assert(mixed.results[2].error ~= nil)
assert(type(mixed.registry) == "table", "Registry should be returned even after partial failure")

local legacy = DiscoverTool.discover({
    mode = "load_tool",
    tool_name = "current_time",
})
assert(legacy and legacy.loaded_count == 1, "Single-name load should remain compatible")

local invalid = DiscoverTool.discover({
    mode = "load_tool",
    tool_names = {},
})
assert(invalid == nil, "An empty batch should be rejected")

print("discover_tool batch-loading tests passed")
