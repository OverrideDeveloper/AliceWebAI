-- Regression tests for the VirtualBox guest-execution adapter.
-- Lua 5.1 / Luvit compatible.

local VMExecution = require("../vm_execution")

assert(VMExecution._base64_encode("") == "")
assert(VMExecution._base64_encode("f") == "Zg==")
assert(VMExecution._base64_encode("fo") == "Zm8=")
assert(VMExecution._base64_encode("foo") == "Zm9v")
assert(VMExecution._base64_encode("Alice's shell script") == "QWxpY2UncyBzaGVsbCBzY3JpcHQ=")

local argv = VMExecution._build_arguments({
    vm_name = "Alice Debian",
    guest_user = "alice-exec",
    password_file = "C:\\secure\\guest password.txt",
}, "printf safe", 10)
assert(argv[3] == "Alice Debian", "VM names with spaces must remain one argument")
assert(argv[10] == "C:\\secure\\guest password.txt", "Password-file paths with spaces must remain one argument")
assert(argv[14] == "20000", "The host timeout must allow guest timeout cleanup")
assert(argv[19] == VMExecution._base64_encode("printf safe"), "Guest code must be transported as base64")

local script = VMExecution._build_guest_script(30)
assert(script:find("timeout --signal=TERM --kill-after=2s 30s /bin/sh", 1, true))
assert(script:find("__ALICE_VM_EXIT_CODE__=", 1, true))

local output, exit_code = VMExecution._strip_exit_marker("hello\n__ALICE_VM_EXIT_CODE__=7\n")
assert(output == "hello")
assert(exit_code == 7)

output, exit_code = VMExecution._strip_exit_marker("__ALICE_VM_EXIT_CODE__=0\n")
assert(output == "")
assert(exit_code == 0)

output, exit_code = VMExecution._strip_exit_marker("no marker here")
assert(output == "no marker here")
assert(exit_code == nil)

print("vm_execution.lua tests passed")
