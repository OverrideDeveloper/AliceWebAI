-- Alice Web AI
-- Regression tests for game_state.lua.
-- Lua 5.1 compatible.

local GameState = require("../game_state")

local created = GameState.run({
    operation = "create_session",
    name = "Blackjack table",
    game_type = "blackjack",
})
assert(type(created) == "table" and created.success == true,
    "A session should be created")
local session_id = created.session.session_id
assert(type(session_id) == "string" and session_id ~= "",
    "The tool should return a usable session identifier")

local added = GameState.run({
    operation = "add_player",
    session_id = session_id,
    name = "Mark",
    bankroll = 1000,
})
assert(added.success == true and added.player.bankroll == 1000,
    "A player should be created with the requested bankroll")
local player_id = added.player.player_id

local deducted = GameState.run({
    operation = "adjust_bankroll",
    session_id = session_id,
    player_id = player_id,
    amount = -100,
    reason = "opening wager",
})
assert(deducted.success == true and deducted.balance == 900,
    "A wager should be deducted from the authoritative balance")

local rejected = GameState.run({
    operation = "adjust_bankroll",
    session_id = session_id,
    player_id = player_id,
    amount = -901,
    reason = "invalid wager",
})
assert(rejected.success == false and rejected.error == "insufficient_funds",
    "A deduction that exceeds the balance must be rejected")
assert(rejected.balance == 900,
    "A rejected deduction must leave the balance unchanged")

local paid = GameState.run({
    operation = "adjust_bankroll",
    session_id = session_id,
    player_id = player_id,
    amount = 200,
    reason = "payout",
})
assert(paid.success == true and paid.balance == 1100,
    "Positive adjustments should add funds")

local player = GameState.run({
    operation = "get_player",
    session_id = session_id,
    player_id = player_id,
})
assert(player.success == true and player.player.bankroll == 1100,
    "get_player should return the current authoritative player state")
assert(#player.player.transactions == 2,
    "Successful balance adjustments should be recorded")

local stored = GameState.run({
    operation = "set_value",
    session_id = session_id,
    scope = "player",
    player_id = player_id,
    key = "hit_points",
    value = 17,
})
assert(stored.success == true and stored.value == 17,
    "Custom player state should support scalar values")

local retrieved = GameState.run({
    operation = "get_value",
    session_id = session_id,
    scope = "player",
    player_id = player_id,
    key = "hit_points",
})
assert(retrieved.success == true and retrieved.found == true
    and retrieved.value == 17,
    "Custom player state should be retrievable")

local session_state = GameState.run({
    operation = "get_state",
    session_id = session_id,
})
assert(session_state.success == true
    and session_state.session.player_count == 1,
    "get_state should return the session and its players")

local bad_key = GameState.run({
    operation = "set_value",
    session_id = session_id,
    scope = "player",
    player_id = player_id,
    key = "bankroll",
    value = 999999,
})
assert(type(bad_key) == "string" and bad_key:match("^Error:"),
    "Reserved bankroll state must not be overwritten through set_value")

local bad_session = GameState.run({
    operation = "get_state",
    session_id = "does-not-exist",
})
assert(type(bad_session) == "string" and bad_session:match("^Error:"),
    "Unknown sessions must return an error")

print("game_state.lua tests passed")
