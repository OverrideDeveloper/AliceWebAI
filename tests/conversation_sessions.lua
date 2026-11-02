-- Alice Web AI
-- Regression tests for identity-scoped conversation sessions.
-- Run from the tests directory: luajit conversation_sessions.lua
-- Lua 5.1 compatible.

local Sessions = require("../conversation_sessions")

local alice_identity = {
    provider = "discord",
    user_id = "628323201889337354",
    name = "whatagoodusername",
}

local kram_identity = {
    provider = "discord",
    user_id = "339522356894498818",
    name = "Kram",
}

assert(
    Sessions.identity_key(alice_identity)
        ~= Sessions.identity_key(kram_identity),
    "Different provider user IDs must create different session keys"
)

local store = Sessions.new(3)

store:partition({
    {
        role = "user",
        content = "Kram's private blackjack conversation",
        user_id = kram_identity.user_id,
        user_provider = kram_identity.provider,
        user_name = kram_identity.name,
    },
    {
        role = "assistant",
        content = "Kram-specific reply",
        user_id = kram_identity.user_id,
        user_provider = kram_identity.provider,
        user_name = kram_identity.name,
    },
    {
        role = "user",
        content = "Legacy message without identity",
    },
})

local alice = store:get(alice_identity)
local kram = store:get(kram_identity)

assert(#alice.history == 0, "Alice's session must start empty")
assert(#kram.history == 2, "Kram's two messages must be restored to Kram's session")
assert(#store.legacy_history == 1, "Unscoped legacy history must be quarantined")

alice.history[#alice.history + 1] = {
    role = "user",
    content = "Hello from whatagoodusername",
    user_id = alice_identity.user_id,
    user_provider = alice_identity.provider,
}
alice.history[#alice.history + 1] = {
    role = "assistant",
    content = "Hello, whatagoodusername",
    user_id = alice_identity.user_id,
    user_provider = alice_identity.provider,
}

assert(#alice.history == 2, "Alice's session must contain only her own messages")
assert(#kram.history == 2, "Adding Alice's messages must not alter Kram's history")

alice.overrides[#alice.overrides + 1] = "Alice-only override"
assert(#alice.overrides == 1, "Alice's override should be present")
assert(#kram.overrides == 0, "Alice's override must not affect Kram")

store:replace(alice, {
    {
        role = "user",
        content = "Replacement from Kram must be ignored",
        user_id = kram_identity.user_id,
        user_provider = kram_identity.provider,
    },
    {
        role = "user",
        content = "Alice's replacement history",
        user_id = alice_identity.user_id,
        user_provider = alice_identity.provider,
    },
})

assert(#alice.history == 1, "History replacement must retain only the target identity")
assert(
    alice.history[1].content == "Alice's replacement history",
    "History replacement must not import another identity's messages"
)
assert(#kram.history == 2, "Replacing Alice's history must leave Kram's history unchanged")

for index = 1, 5 do
    alice.history[#alice.history + 1] = {
        role = "user",
        content = "Alice message " .. tostring(index),
        user_id = alice_identity.user_id,
        user_provider = alice_identity.provider,
    }
    store:trim(alice.history)
end

assert(#alice.history == 3, "History cap must apply independently to each identity")
assert(#kram.history == 2, "Alice reaching her history cap must not evict Kram's messages")

local flattened = store:flatten()
assert(#flattened == 6, "Flattened persistence must include both users and quarantined legacy history")

local saw_legacy = false
for _, message in ipairs(flattened) do
    if message.content == "Legacy message without identity" then
        saw_legacy = true
    end
end
assert(saw_legacy, "Quarantined legacy history must remain preserved for compatibility")

print("conversation session tests passed")
