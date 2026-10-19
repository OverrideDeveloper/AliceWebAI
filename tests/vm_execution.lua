-- Regression tests for the VirtualBox guest-execution adapter.
-- Lua 5.1 / Luvit compatible.

local VMExecution = require("../vm_execution")

assert(VMExecution._base64_encode("") == "")
assert(VMExecution._base64_encode("f") == "Zg==")
assert(VMExecution._base64_encode("fo") == "Zm8=")
assert(VMExecution._base64_encode("foo") == "Zm9v")
assert(VMExecution._base64_encode("Alice's shell script") == "QWxpY2UncyBzaGVsbCBzY3JpcHQ=")

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
