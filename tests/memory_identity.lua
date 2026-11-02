-- Run from the repository root with Luvit/LuaJIT:
-- luajit tests/memory_identity.lua

local MemoryIdentity = require("./memory_identity")

local private_context = {
    request_context = {
        anonymous = false,
        memory_owner_id = "discord:12345",
    },
}

local owner, err = MemoryIdentity.owner_id(private_context)
assert(owner == "discord:12345", tostring(err))

local anonymous_owner, anonymous_error = MemoryIdentity.owner_id({
    request_context = {
        anonymous = true,
        memory_owner_id = "local:local-anonymous",
    },
})
assert(anonymous_owner == nil)
assert(anonymous_error ~= nil)

local missing_owner, missing_error = MemoryIdentity.owner_id({
    request_context = {
        anonymous = false,
    },
})
assert(missing_owner == nil)
assert(missing_error ~= nil)

local missing_context, context_error = MemoryIdentity.owner_id(nil)
assert(missing_context == nil)
assert(context_error ~= nil)

print("memory_identity tests passed")
