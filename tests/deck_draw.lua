-- Alice Web AI
-- Regression tests for persistent and one-off deck draws.
-- Lua 5.1 compatible.

local DeckDraw = require("../deck_draw")

local function draw(deck, count, persist_state)
    return DeckDraw.draw({
        deck = deck,
        count = count,
        persist_state = persist_state,
    })
end

local invalid_deck = draw("not_a_deck", 1)
assert(type(invalid_deck) == "string" and invalid_deck:match("^Error:"),
    "Unknown decks must return an error")

local invalid_count = draw("standard_playing_cards", 0)
assert(type(invalid_count) == "string" and invalid_count:match("^Error:"),
    "Counts below one must return an error")

local invalid_persist_state = draw("standard_playing_cards", 1, "false")
assert(type(invalid_persist_state) == "string"
    and invalid_persist_state:match("^Error:"),
    "persist_state must be a boolean when supplied")

local first_cycle = {}
for i = 1, 52 do
    local result = draw("standard_playing_cards", 1)
    assert(type(result) == "table", "A valid draw should return a result object")
    assert(result.drawn_count == 1, "A one-card draw should return one card")
    assert(result.persist_state == true,
        "Omitting persist_state should preserve the default persistent behavior")

    local card = result.drawn[1]
    assert(type(card) == "table" and card.id ~= nil,
        "A drawn card should retain its source record")
    assert(not first_cycle[card.id], "A card must not repeat within one cycle")
    first_cycle[card.id] = true

    if i < 52 then
        assert(result.reshuffled == false, "The deck should not reshuffle before exhaustion")
    else
        assert(result.reshuffled == true, "The deck should reshuffle when exhausted")
        assert(result.remaining == 52, "The next cycle should be ready after exhaustion")
    end
end

local first_cycle_count = 0
for _ in pairs(first_cycle) do
    first_cycle_count = first_cycle_count + 1
end
assert(first_cycle_count == 52, "The first cycle should contain all 52 unique cards")

local second_cycle = {}
for i = 1, 51 do
    local result = draw("standard_playing_cards", 1)
    local card = result.drawn[1]
    assert(not second_cycle[card.id], "A card must not repeat within the second cycle")
    second_cycle[card.id] = true
end

local final_draw = draw("standard_playing_cards", 3)
assert(final_draw.drawn_count == 1,
    "A request larger than the remaining pool should return only the remaining entries")
assert(final_draw.reshuffled == true,
    "Exhausting the remaining pool should trigger a reshuffle")
assert(final_draw.remaining == 52,
    "The next cycle should be ready after a partial final draw")

local tarot = draw("tarot_rider_waite_smith", 1)
assert(type(tarot) == "table" and tarot.drawn_count == 1,
    "Tarot decks should be supported")
assert(tarot.drawn[1].name ~= nil,
    "Tarot draws should return the original structured record")

-- A one-off draw must not consume entries from the persistent deck.
local before_one_off = draw("standard_playing_cards", 1)
assert(before_one_off.remaining == 51,
    "A persistent one-card draw should leave 51 cards")

local one_off = draw("standard_playing_cards", 7, false)
assert(type(one_off) == "table" and one_off.drawn_count == 7,
    "A non-persistent draw should return the requested entries")
assert(one_off.persist_state == false,
    "The result should report that state was not persisted")
assert(one_off.remaining == 45,
    "A one-off draw should report the unused entries in its temporary pool")
assert(one_off.reshuffled == false,
    "A one-off draw should not report a persistent reshuffle")

local after_one_off = draw("standard_playing_cards", 1)
assert(after_one_off.remaining == 50,
    "A one-off draw must not change the persistent deck's remaining count")

local tarot_one_off = draw("tarot_rider_waite_smith", 3, false)
assert(tarot_one_off.drawn_count == 3 and tarot_one_off.persist_state == false,
    "One-off draws should also work for Tarot")

print("deck_draw.lua tests passed")
