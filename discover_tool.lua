-- Alice Web AI
-- Discover and manage registered model-facing tool definitions.
-- Lua 5.1 / Luvit compatible.

local ToolRegistry = require("./tool_registry")

local M = {}

M.definition = {
    type = "function",
    ["function"] = {
        name = "discover_tool",
        description =
            "Discover registered tools and manage which tool definitions are exposed "
            .. "to the inference model. Use mode All to list tool names, synopses, and "
            .. "loaded states; mode tool_name to retrieve a full tool definition; "
            .. "mode load_tool to load a registered tool; or mode unload_tool to unload "
            .. "one of the permitted unloadable tools.",
        parameters = {
            type = "object",
            properties = {
                mode = {
                    type = "string",
                    enum = {"All", "tool_name", "load_tool", "unload_tool"},
                    description =
                        "Operation: All, tool_name, load_tool, or unload_tool.",
                },
                tool_name = {
                    type = "string",
                    description =
                        "Required for tool_name, load_tool, and unload_tool; the exact registered tool name.",
                },
            },
            required = {"mode"},
        },
    },
}

function M.discover(arguments)
    arguments = type(arguments) == "table" and arguments or {}
    local mode = arguments.mode

    if mode == "All" then
        return {
            tools = ToolRegistry.list(),
        }
    end

    if mode == "tool_name" then
        local name = arguments.tool_name
        if type(name) ~= "string" or name == "" then
            return nil, {
                category = "invalid_request",
                message = "discover_tool mode tool_name requires tool_name",
            }
        end

        local entry = ToolRegistry.get(name)
        if not entry then
            return nil, {
                category = "unknown_tool",
                message = "Unknown tool: " .. name,
            }
        end

        return {
            tool_name = entry.tool_name,
            description = entry.description,
            synopsis = entry.synopsis,
            loaded = entry.loaded,
        }
    end

    if mode == "load_tool" then
        local name = arguments.tool_name
        if type(name) ~= "string" or name == "" then
            return nil, {
                category = "invalid_request",
                message = "discover_tool mode load_tool requires tool_name",
            }
        end

        local result, err = ToolRegistry.load(name)
        if not result then
            return nil, {
                category = "unknown_tool",
                message = err,
            }
        end

        result.message = result.changed
            and ("Loaded tool " .. name .. "; its definition will be available on the next inference round.")
            or ("Tool " .. name .. " is already loaded.")
        return result
    end

    if mode == "unload_tool" then
        local name = arguments.tool_name
        if type(name) ~= "string" or name == "" then
            return nil, {
                category = "invalid_request",
                message = "discover_tool mode unload_tool requires tool_name",
            }
        end

        local result, err = ToolRegistry.unload(name)
        if not result then
            return nil, {
                category = "tool_unload_denied",
                message = err,
            }
        end

        result.message = result.changed
            and ("Unloaded tool " .. name .. "; new inference rounds will no longer receive its definition.")
            or ("Tool " .. name .. " is already unloaded.")
        return result
    end

    return nil, {
        category = "invalid_request",
        message = "Unsupported discover_tool mode. Use All, tool_name, load_tool, or unload_tool.",
    }
end

return M
