-- Alice Web AI
-- Linux guest execution through VirtualBox Guest Additions.
-- Lua 5.1 / Luvit compatible.

local childprocess = require("childprocess")
local timer = require("timer")
local uv = require("uv")

local M = {}

local DEFAULT_TIMEOUT_SECONDS = 30
local DEFAULT_MAX_TIMEOUT_SECONDS = 120
local DEFAULT_MAX_OUTPUT_BYTES = 8192
local MAX_COMMAND_BYTES = 16384
local EXIT_MARKER = "__ALICE_VM_EXIT_CODE__="

local function get_env(name)
    if process and type(process.env) == "table" then
        local value = process.env[name]
        if value ~= nil then
            return tostring(value)
        end
    end

    if os and type(os.getenv) == "function" then
        return os.getenv(name)
    end

    return nil
end

local function parse_boolean(value, default)
    if value == nil or value == "" then return default end
    value = tostring(value):lower()
    return value == "true" or value == "1" or value == "yes" or value == "on"
end

local function parse_integer(value, default, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= math.floor(number) then
        return default
    end
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

local function read_config()
    local config = {
        enabled = parse_boolean(get_env("ALICE_VM_ENABLED"), false),
        vm_name = get_env("ALICE_VM_NAME"),
        guest_user = get_env("ALICE_VM_GUEST_USER"),
        password_file = get_env("ALICE_VM_GUEST_PASSWORD_FILE"),
        vboxmanage = get_env("ALICE_VM_VBOXMANAGE_PATH"),
        default_timeout_seconds = parse_integer(
            get_env("ALICE_VM_TIMEOUT_SECONDS"),
            DEFAULT_TIMEOUT_SECONDS, 1, 600
        ),
        max_timeout_seconds = parse_integer(
            get_env("ALICE_VM_MAX_TIMEOUT_SECONDS"),
            DEFAULT_MAX_TIMEOUT_SECONDS, 1, 600
        ),
        max_output_bytes = parse_integer(
            get_env("ALICE_VM_MAX_OUTPUT_BYTES"),
            DEFAULT_MAX_OUTPUT_BYTES, 1024, 262144
        ),
    }
    if config.default_timeout_seconds > config.max_timeout_seconds then
        config.default_timeout_seconds = config.max_timeout_seconds
    end
    return config
end

local function base64_encode(input)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local output = {}

    for index = 1, #input, 3 do
        local first = input:byte(index)
        local second = input:byte(index + 1)
        local third = input:byte(index + 2)

        second = second or 0
        third = third or 0

        local combined = first * 65536 + second * 256 + third
        local a = math.floor(combined / 262144) % 64 + 1
        local b = math.floor(combined / 4096) % 64 + 1
        local c = math.floor(combined / 64) % 64 + 1
        local d = combined % 64 + 1

        output[#output + 1] = alphabet:sub(a, a)
        output[#output + 1] = alphabet:sub(b, b)
        output[#output + 1] = index + 1 <= #input and alphabet:sub(c, c) or "="
        output[#output + 1] = index + 2 <= #input and alphabet:sub(d, d) or "="
    end

    return table.concat(output)
end

local function build_guest_script(timeout_seconds)
    -- The actual user script is passed as a base64 argument. It is decoded
    -- inside the guest and fed to /bin/sh on stdin; user text is never
    -- concatenated into shell syntax.
    return "printf '%s' \"$1\" | base64 -d | timeout --signal=TERM --kill-after=2s "
        .. tostring(timeout_seconds)
        .. "s /bin/sh; rc=$?; printf '\\n"
        .. EXIT_MARKER
        .. "%s\\n' \"$rc\"; exit 0"
end

local function build_arguments(config, command, timeout_seconds)
    local encoded = base64_encode(command)
    local host_timeout_ms = (timeout_seconds + 10) * 1000

    return {
        "--nologo",
        "guestcontrol", config.vm_name, "run",
        "--exe", "/bin/sh",
        "--username", config.guest_user,
        "--passwordfile", config.password_file,
        "--wait-stdout",
        "--wait-stderr",
        "--timeout", tostring(host_timeout_ms),
        "--", "-c", build_guest_script(timeout_seconds),
        "alice-vm", encoded,
    }
end

local function strip_exit_marker(stdout)
    local prefix, code, suffix = stdout:match("^(.*)\n" .. EXIT_MARKER .. "(%d+)\r?\n?$")
    if code then
        return prefix, tonumber(code)
    end

    code = stdout:match("^" .. EXIT_MARKER .. "(%d+)\r?\n?$")
    if code then return "", tonumber(code) end

    return stdout, nil
end

local function error_result(category, message, extra)
    local result = extra or {}
    result.category = category
    result.message = message
    return result
end

function M.is_enabled()
    return read_config().enabled
end

function M.execute(arguments, callback)
    if type(callback) ~= "function" then
        return nil, "vm_execute requires a callback"
    end

    arguments = type(arguments) == "table" and arguments or {}
    local config = read_config()

    if not config.enabled then
        callback(nil, error_result(
            "vm_execution_disabled",
            "VM execution is disabled. Set ALICE_VM_ENABLED=true and configure the VirtualBox VM settings."
        ))
        return
    end

    local command = arguments.command
    if command == nil then command = arguments.code end
    if type(command) ~= "string" or command:match("^%s*$") then
        callback(nil, error_result(
            "invalid_request",
            "Provide a non-empty command string to execute in the Linux guest."
        ))
        return
    end
    if #command > MAX_COMMAND_BYTES then
        callback(nil, error_result(
            "command_too_large",
            "The command exceeds the 16384-byte limit for safe Windows command-line transport."
        ))
        return
    end
    if command:find("%z") then
        callback(nil, error_result(
            "invalid_request",
            "The command contains a NUL byte, which is not supported."
        ))
        return
    end

    local missing = {}
    if not config.vm_name or config.vm_name == "" then missing[#missing + 1] = "ALICE_VM_NAME" end
    if not config.guest_user or config.guest_user == "" then missing[#missing + 1] = "ALICE_VM_GUEST_USER" end
    if not config.password_file or config.password_file == "" then missing[#missing + 1] = "ALICE_VM_GUEST_PASSWORD_FILE" end
    if not config.vboxmanage or config.vboxmanage == "" then missing[#missing + 1] = "ALICE_VM_VBOXMANAGE_PATH" end
    if #missing > 0 then
        callback(nil, error_result(
            "vm_execution_not_configured",
            "VM execution is enabled but these settings are missing: " .. table.concat(missing, ", ")
        ))
        return
    end

    local timeout_seconds = config.default_timeout_seconds
    if arguments.timeout_seconds ~= nil then
        local requested = tonumber(arguments.timeout_seconds)
        if not requested or requested ~= math.floor(requested) or requested < 1 then
            callback(nil, error_result(
                "invalid_request",
                "timeout_seconds must be a whole number greater than zero."
            ))
            return
        end
        timeout_seconds = requested
    end

    if timeout_seconds > config.max_timeout_seconds then
        callback(nil, error_result(
            "timeout_limit_exceeded",
            "timeout_seconds exceeds the configured maximum of "
                .. tostring(config.max_timeout_seconds) .. " seconds."
        ))
        return
    end

    local started_at = uv.now()
    local stdout_parts, stderr_parts = {}, {}
    local stdout_bytes, stderr_bytes = 0, 0
    local stdout_truncated, stderr_truncated = false, false
    local output_limit_hit = false
    local timed_out = false
    local completed = false
    local child
    local timeout_handle

    local function finish(result, err)
        if completed then return end
        completed = true
        if timeout_handle then
            timer.clearTimeout(timeout_handle)
            timeout_handle = nil
        end
        callback(result, err)
    end

    local function append_output(which, chunk)
        if completed then return end
        local parts, current_bytes, truncated
        if which == "stdout" then
            parts, current_bytes, truncated = stdout_parts, stdout_bytes, stdout_truncated
        else
            parts, current_bytes, truncated = stderr_parts, stderr_bytes, stderr_truncated
        end

        local remaining = config.max_output_bytes - current_bytes
        if remaining > 0 then
            parts[#parts + 1] = chunk:sub(1, remaining)
            current_bytes = current_bytes + math.min(#chunk, remaining)
        end
        if #chunk > remaining then
            truncated = true
            output_limit_hit = true
            if child then child:kill("sigterm") end
        end

        if which == "stdout" then
            stdout_bytes, stdout_truncated = current_bytes, truncated
        else
            stderr_bytes, stderr_truncated = current_bytes, truncated
        end
    end

    local argv = build_arguments(config, command, timeout_seconds)
    print("[VM execute] vm=" .. config.vm_name
        .. " guest_user=" .. config.guest_user
        .. " timeout_seconds=" .. tostring(timeout_seconds)
        .. " command_bytes=" .. tostring(#command))

    local spawn_ok, spawn_error = pcall(function()
        child = childprocess.spawn(config.vboxmanage, argv)
    end)
    if not spawn_ok or not child then
        finish(nil, error_result(
            "vm_process_start_failed",
            "Could not start VBoxManage: " .. tostring(spawn_error)
        ))
        return
    end

    child.stdout:on("data", function(chunk)
        append_output("stdout", chunk)
    end)
    child.stderr:on("data", function(chunk)
        append_output("stderr", chunk)
    end)

    child:once("error", function(err)
        finish(nil, error_result(
            "vm_process_error",
            "VBoxManage process error: " .. tostring(err),
            {
                stdout = table.concat(stdout_parts),
                stderr = table.concat(stderr_parts),
                duration_ms = math.max(0, uv.now() - started_at),
            }
        ))
    end)

    child:once("close", function(host_exit_code, signal)
        local stdout = table.concat(stdout_parts)
        local stderr = table.concat(stderr_parts)
        local guest_stdout, guest_exit_code = strip_exit_marker(stdout)
        local duration_ms = math.max(0, uv.now() - started_at)

        if timed_out then
            finish(nil, error_result(
                "vm_execution_timeout",
                "The VBoxManage execution exceeded its host-side timeout.",
                {
                    stdout = guest_stdout,
                    stderr = stderr,
                    duration_ms = duration_ms,
                    timed_out = true,
                    host_exit_code = host_exit_code,
                    signal = signal,
                }
            ))
            return
        end

        if output_limit_hit then
            finish(nil, error_result(
                "vm_output_limit_exceeded",
                "Guest output exceeded the configured per-stream byte limit; execution was stopped.",
                {
                    stdout = guest_stdout,
                    stderr = stderr,
                    duration_ms = duration_ms,
                    exit_code = guest_exit_code,
                    stdout_truncated = stdout_truncated,
                    stderr_truncated = stderr_truncated,
                    host_exit_code = host_exit_code,
                }
            ))
            return
        end

        if guest_exit_code == nil then
            finish(nil, error_result(
                "vm_execution_failed",
                "VBoxManage did not return the guest exit-code marker. Check VirtualBox Guest Additions and the VM configuration.",
                {
                    stdout = stdout,
                    stderr = stderr,
                    duration_ms = duration_ms,
                    host_exit_code = host_exit_code,
                    signal = signal,
                }
            ))
            return
        end

        finish({
            vm = config.vm_name,
            guest_user = config.guest_user,
            command_bytes = #command,
            status = guest_exit_code == 0 and "success" or "command_failed",
            exit_code = guest_exit_code,
            duration_ms = duration_ms,
            timed_out = guest_exit_code == 124 or guest_exit_code == 137,
            stdout = guest_stdout,
            stderr = stderr,
            stdout_truncated = stdout_truncated,
            stderr_truncated = stderr_truncated,
            host_exit_code = host_exit_code,
        }, nil)
    end)

    timeout_handle = timer.setTimeout((timeout_seconds + 20) * 1000, function()
        if completed then return end
        timed_out = true
        if child then child:kill("sigterm") end
    end)
end

M._base64_encode = base64_encode
M._build_guest_script = build_guest_script
M._build_arguments = build_arguments
M._strip_exit_marker = strip_exit_marker

M.definition = {
    type = "function",
    ["function"] = {
        name = "vm_execute",
        description =
            "Execute a shell command or multi-line shell script inside Alice's configured Debian/Linux VirtualBox guest. "
            .. "This runs as the configured unprivileged guest account, not on the Windows host. "
            .. "Returns the guest exit code, stdout, stderr, and elapsed time. "
            .. "Use timeout_seconds only when a different execution limit is needed; commands are bounded by the configured maximum.",
        parameters = {
            type = "object",
            properties = {
                command = {
                    type = "string",
                    description = "Required. Shell command or multi-line shell script to execute inside the Linux guest.",
                },
                timeout_seconds = {
                    type = "integer",
                    description = "Optional. Execution timeout in seconds; must not exceed the configured maximum.",
                },
            },
            required = {"command"},
        },
    },
}

return M
