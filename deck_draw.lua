-- Alice Web AI
--
-- Copyright (C) 2026 Override Development
--
-- This file is part of Alice Web AI.
--
-- Alice Web AI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- https://www.gnu.org/licenses/.
--
-- deck_draw.lua
-- Draw from named decks, optionally keeping each active deck's state in memory.
-- Lua 5.1 compatible.

local json = require("./json")

local M = {}

local DECKS_PATH = "decks.json"

-- Definitions are decoded once. Persistent draw state is maintained per deck.
local deck_definitions = nil
local deck_states = {}
local random_seeded = false

local function seed_random()
    if random_seeded then
        return
    end

    -- Include process CPU time so two modules initialized in the same second
    -- are less likely to reset the shared Lua RNG to the same seed.
    math.randomseed(os.time() + math.floor(os.clock() * 100000))
    math.random()
    math.random()
    math.random()

    random_seeded = true
end

local function shuffled_copy(entries)
    local copy = {}

    for i, entry in ipairs(entries) do
        copy[i] = entry
    end

    seed_random()

    for i = #copy, 2, -1 do
        local j = math.random(i)
        copy[i], copy[j] = copy[j], copy[i]
    end

    return copy
end

local function load_definitions()
    if deck_definitions then
        return deck_definitions
    end

    local file, open_error = io.open(DECKS_PATH, "rb")
    if not file then
        return nil, "Unable to open " .. DECKS_PATH .. ": " .. tostring(open_error)
    end

    local contents, read_error = file:read("*a")
    file:close()

    if not contents then
        return nil, "Unable to read " .. DECKS_PATH .. ": " .. tostring(read_error)
    end

    local decoded, _, decode_error = json.decode(contents, 1, nil)
    if type(decoded) ~= "table" or type(decoded.decks) ~= "table" then
        return nil, "Unable to parse " .. DECKS_PATH .. ": "
            .. tostring(decode_error or "expected a decks object")
    end

    deck_definitions = decoded.decks
    return deck_definitions
end

local function get_deck_entries(deck_name)
    if type(deck_name) ~= "string" or deck_name == "" then
        return nil, "deck is required"
    end

    local definitions, load_error = load_definitions()
    if not definitions then
        return nil, load_error
    end

    local entries = definitions[deck_name]
    if type(entries) ~= "table" or #entries == 0 then
        return nil, "unknown or empty deck: " .. deck_name
    end

    for _, entry in ipairs(entries) do
        if type(entry) ~= "table" then
            return nil, "deck contains an invalid entry: " .. deck_name
        end
    end

    return entries
end

local function get_deck_state(deck_name, entries)
    local state = deck_states[deck_name]
    if state then
        return state
    end

    if not entries then
        local entries_error
        entries, entries_error = get_deck_entries(deck_name)
        if not entries then
            return nil, entries_error
        end
    end

    state = {
        entries = entries,
        remaining = shuffled_copy(entries),
        total = #entries,
    }

    deck_states[deck_name] = state
    return state
end

function M.draw(arguments)
    if type(arguments) ~= "table" then
        return "Error: arguments must be an object"
    end

    local persist_state = arguments.persist_state
    if persist_state == nil then
        -- Preserve the original stateful behavior unless explicitly disabled.
        persist_state = true
    end

    if type(persist_state) ~= "boolean" then
        return "Error: persist_state must be a boolean"
    end

    local deck_name = arguments.deck
    local state
    local entries
    local total

    if persist_state then
        local state_error
        state, state_error = get_deck_state(deck_name)
        if not state then
            return "Error: " .. tostring(state_error)
        end
        total = state.total
    else
        local entries_error
        entries, entries_error = get_deck_entries(deck_name)
        if not entries then
            return "Error: " .. tostring(entries_error)
        end
        total = #entries
    end

    local count = arguments.count
    if count == nil then
        count = 1
    end

    if type(count) ~= "number"
        or count % 1 ~= 0
        or count < 1
        or count > total then
        return "Error: count must be an integer between 1 and "
            .. tostring(total)
    end

    -- A non-persistent draw starts from a freshly shuffled copy each time.
    -- It is unique within this call but neither reads nor changes deck_states.
    local remaining_pool
    if persist_state then
        remaining_pool = state.remaining
    else
        remaining_pool = shuffled_copy(entries)
    end

    local drawn = {}
    local reshuffled = false

    -- A single request never crosses into a new cycle. For persistent draws,
    -- exhaustion resets the shared deck for the next call. One-off draws have
    -- no shared cycle to reset.
    while #drawn < count and #remaining_pool > 0 do
        drawn[#drawn + 1] = table.remove(remaining_pool)
    end

    if persist_state and #remaining_pool == 0 then
        state.remaining = shuffled_copy(state.entries)
        reshuffled = true
    end

    return {
        deck = deck_name,
        drawn = drawn,
        requested_count = count,
        drawn_count = #drawn,
        deck_size = total,
        remaining = #remaining_pool,
        persist_state = persist_state,
        reshuffled = reshuffled,
    }
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "deck_draw",
        description =
            "Draw one or more entries from a named deck without replacement. "
            .. "Use the exact deck key: standard_playing_cards, tarot_rider_waite_smith, "
            .. "elder_futhark_runes, or i_ching_king_wen. Set persist_state=true to keep "
            .. "the deck's remaining entries in server memory across calls; this defaults "
            .. "to true for compatibility. Set persist_state=false for a one-off draw from "
            .. "a freshly shuffled deck; it will not read or modify persistent draw state. "
            .. "Persistent decks automatically reshuffle when exhausted. If fewer entries "
            .. "remain than requested, a persistent draw returns only those remaining entries "
            .. "and reshuffles; one call never spans two cycles. Never invent a draw; use "
            .. "this tool for actual random selections.",
        parameters = {
            type = "object",
            properties = {
                deck = {
                    type = "string",
                    enum = {
                        "standard_playing_cards",
                        "tarot_rider_waite_smith",
                        "elder_futhark_runes",
                        "i_ching_king_wen",
                    },
                    description = "Exact key of the deck to draw from.",
                },
                count = {
                    type = "integer",
                    minimum = 1,
                    maximum = 78,
                    description = "Number of entries to draw; defaults to 1.",
                },
                persist_state = {
                    type = "boolean",
                    description =
                        "Keep this deck's remaining entries in server memory across calls. "
                        .. "Defaults to true; set false for a one-off draw.",
                },
            },
            required = {
                "deck",
            },
        },
    },
}

return M
