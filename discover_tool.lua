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
            "Use this tool whenever a capability needed for the current request is not "
            .. "available among the currently loaded tool definitions. An absent definition "
            .. "does not mean the capability is unavailable. First use mode All to list "
            .. "registered tool names, synopses, and loaded states. If needed, use mode "
            .. "tool_name with the exact name to inspect its full definition. Use mode "
            .. "load_tool with tool_names to load several registered tools in one operation, "
            .. "or tool_name to load one tool. After loading, the result includes the updated "
            .. "registry and each tool definition is supplied on the next inference round. "
            .. "Discovery or inspection alone does not load a tool. Use mode unload_tool "
            .. "only for a permitted unloadable tool.",
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
                        "Exact registered tool name for tool_name, load_tool, or unload_tool. "
                        .. "For load_tool, use tool_names to load multiple tools at once.",
                },
                tool_names = {
                    type = "array",
                    items = {type = "string"},
                    description =
                        "One or more exact registered tool names to load in a single load_tool operation.",
                },
            },
            required = {"mode"},
        },
    },
}

local function get_requested_names(arguments, mode)
    if type(arguments.tool_names) == "table" then
        if #arguments.tool_names == 0 then
            return nil, "tool_names must contain at least one tool name"
        end

        local names = {}
        for index, name in ipairs(arguments.tool_names) do
            if type(name) ~= "string" or name == "" then
                return nil, "tool_names entry " .. index .. " must be a non-empty string"
            end
            names[#names + 1] = name
        end
        return names
    end

    local name = arguments.tool_name
    if type(name) ~= "string" or name == "" then
        return nil, "discover_tool mode " .. mode .. " requires tool_name or tool_names"
    end

    return {name}
end

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
        local names, names_error = get_requested_names(arguments, mode)
        if not names then
            return nil, {
                category = "invalid_request",
                message = names_error,
            }
        end

        local results = {}
        local loaded_count = 0
        local failed_count = 0

        for _, name in ipairs(names) do
            local result, err = ToolRegistry.load(name)
            if result then
                loaded_count = loaded_count + 1
                results[#results + 1] = {
                    tool_name = result.tool_name,
                    synopsis = result.synopsis,
                    loaded = result.loaded,
                    changed = result.changed,
                }
            else
                failed_count = failed_count + 1
                results[#results + 1] = {
                    tool_name = name,
                    loaded = false,
                    error = err,
                }
            end
        end

        local message = string.format(
            "Load operation complete: %d loaded or already loaded, %d failed. "
                .. "The updated registry is included below; newly loaded tool definitions "
                .. "will be available on the next inference round.",
            loaded_count,
            failed_count
        )

        return {
            results = results,
            registry = ToolRegistry.list(),
            loaded_count = loaded_count,
            failed_count = failed_count,
            message = message,
        }
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
