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
-- game_state.lua
-- In-memory state for multi-turn games: sessions, players, bankrolls,
-- and extensible session/player key-value state.
-- Lua 5.1 compatible.

local M = {}

local sessions = {}
local next_session_id = 1

local function is_nonempty_string(value)
    return type(value) == "string" and value:match("^%s*$") == nil
end

local function find_session(session_id)
    if not is_nonempty_string(session_id) then
        return nil, "session_id is required"
    end

    local session = sessions[session_id]
    if not session then
        return nil, "unknown session: " .. session_id
    end

    return session
end

local function find_player(session, player_id)
    if not is_nonempty_string(player_id) then
        return nil, "player_id is required"
    end

    local player = session.players[player_id]
    if not player then
        return nil, "unknown player: " .. player_id
    end

    return player
end

local function copy_table(source)
    local result = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            result[key] = copy_table(value)
        else
            result[key] = value
        end
    end
    return result
end

local function snapshot_session(session)
    local result = {
        session_id = session.session_id,
        name = session.name,
        game_type = session.game_type,
        created_at = session.created_at,
        state = copy_table(session.state),
        players = {},
        player_count = 0,
    }

    for player_id, player in pairs(session.players) do
        result.players[player_id] = copy_table(player)
        result.player_count = result.player_count + 1
    end

    return result
end

local function validate_key(key)
    if not is_nonempty_string(key) then
        return nil, "key is required"
    end
    if key == "session_id" or key == "players" or key == "transactions"
        or key == "bankroll" or key == "player_id" then
        return nil, "key is reserved and cannot be changed through set_value"
    end
    return true
end

function M.run(arguments)
    if type(arguments) ~= "table" then
        return "Error: arguments must be an object"
    end

    local operation = arguments.operation
    if not is_nonempty_string(operation) then
        return "Error: operation is required"
    end

    if operation == "create_session" then
        local session_id = arguments.session_id
        if session_id ~= nil and not is_nonempty_string(session_id) then
            return "Error: session_id must be a non-empty string when supplied"
        end

        if not session_id then
            session_id = "session-" .. tostring(next_session_id)
            next_session_id = next_session_id + 1
            while sessions[session_id] do
                session_id = "session-" .. tostring(next_session_id)
                next_session_id = next_session_id + 1
            end
        elseif sessions[session_id] then
            return "Error: session already exists: " .. session_id
        end

        local session = {
            session_id = session_id,
            name = tostring(arguments.name or session_id),
            game_type = tostring(arguments.game_type or "general"),
            created_at = os.time(),
            state = {},
            players = {},
            next_player_id = 1,
        }
        sessions[session_id] = session
        return {
            success = true,
            operation = operation,
            session = snapshot_session(session),
        }
    end

    local session, session_error = find_session(arguments.session_id)
    if not session then
        return "Error: " .. session_error
    end

    if operation == "get_state" then
        return {
            success = true,
            operation = operation,
            session = snapshot_session(session),
        }
    end

    if operation == "add_player" then
        local name = arguments.name
        if not is_nonempty_string(name) then
            return "Error: name is required to add a player"
        end

        local player_id = arguments.player_id
        if player_id ~= nil and not is_nonempty_string(player_id) then
            return "Error: player_id must be a non-empty string when supplied"
        end
        if not player_id then
            player_id = "player-" .. tostring(session.next_player_id)
            session.next_player_id = session.next_player_id + 1
            while session.players[player_id] do
                player_id = "player-" .. tostring(session.next_player_id)
                session.next_player_id = session.next_player_id + 1
            end
        elseif session.players[player_id] then
            return "Error: player already exists in this session: " .. player_id
        end

        local bankroll = arguments.bankroll
        if bankroll == nil then
            bankroll = 0
        end
        if type(bankroll) ~= "number" or bankroll ~= bankroll
            or bankroll == math.huge or bankroll == -math.huge or bankroll < 0 then
            return "Error: bankroll must be a non-negative number"
        end

        local player = {
            player_id = player_id,
            name = name,
            bankroll = bankroll,
            state = {},
            transactions = {},
        }
        session.players[player_id] = player

        return {
            success = true,
            operation = operation,
            player = copy_table(player),
            session_id = session.session_id,
        }
    end

    if operation == "get_player" or operation == "adjust_bankroll"
        or operation == "set_value" or operation == "get_value" then
        local scope = arguments.scope
        if scope == nil and (operation == "adjust_bankroll") then
            scope = "player"
        end
        if scope ~= "session" and scope ~= "player" then
            return "Error: scope must be 'session' or 'player'"
        end

        local target
        if scope == "player" then
            local player, player_error = find_player(session, arguments.player_id)
            if not player then
                return "Error: " .. player_error
            end
            target = player
        else
            target = session
        end

        if operation == "get_player" then
            if scope ~= "player" then
                return "Error: get_player requires scope='player'"
            end
            return {
                success = true,
                operation = operation,
                session_id = session.session_id,
                player = copy_table(target),
            }
        end

        if operation == "adjust_bankroll" then
            if scope ~= "player" then
                return "Error: bankroll belongs to a player; scope must be 'player'"
            end
            local amount = arguments.amount
            if type(amount) ~= "number" or amount ~= amount
                or amount == math.huge or amount == -math.huge or amount == 0 then
                return "Error: amount must be a finite non-zero number"
            end

            local new_balance = target.bankroll + amount
            if new_balance < 0 then
                return {
                    success = false,
                    operation = operation,
                    error = "insufficient_funds",
                    message = "Adjustment rejected: bankroll cannot become negative",
                    player_id = target.player_id,
                    balance = target.bankroll,
                    requested_change = amount,
                }
            end

            target.bankroll = new_balance
            local transaction = {
                amount = amount,
                balance_after = new_balance,
                reason = tostring(arguments.reason or "unspecified"),
                timestamp = os.time(),
            }
            target.transactions[#target.transactions + 1] = transaction

            return {
                success = true,
                operation = operation,
                player_id = target.player_id,
                amount = amount,
                balance = new_balance,
                transaction = copy_table(transaction),
            }
        end

        local key_ok, key_error = validate_key(arguments.key)
        if not key_ok then
            return "Error: " .. key_error
        end

        local state = scope == "player" and target.state or session.state
        if operation == "set_value" then
            if arguments.value == nil then
                return "Error: value is required"
            end
            state[arguments.key] = copy_table(arguments.value)
            return {
                success = true,
                operation = operation,
                scope = scope,
                session_id = session.session_id,
                player_id = scope == "player" and target.player_id or nil,
                key = arguments.key,
                value = copy_table(state[arguments.key]),
            }
        end

        if state[arguments.key] == nil then
            return {
                success = true,
                operation = operation,
                found = false,
                scope = scope,
                session_id = session.session_id,
                player_id = scope == "player" and target.player_id or nil,
                key = arguments.key,
            }
        end
        return {
            success = true,
            operation = operation,
            found = true,
            scope = scope,
            session_id = session.session_id,
            player_id = scope == "player" and target.player_id or nil,
            key = arguments.key,
            value = copy_table(state[arguments.key]),
        }
    end

    return "Error: unsupported operation: " .. operation
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "game_state",
        description =
            "Maintain authoritative in-memory state for ongoing games. "
            .. "Use create_session first, then use the returned session_id for later operations. "
            .. "Sessions contain players; each player has an independent bankroll and player state. "
            .. "Use add_player to register a participant, get_state to retrieve the complete session, "
            .. "get_player to retrieve one player, and adjust_bankroll to apply a validated signed "
            .. "change (negative amounts spend money; insufficient funds are rejected). "
            .. "Use set_value/get_value for additional session- or player-scoped structured state. "
            .. "State survives tool calls while this Alice server process runs, but is lost when "
            .. "the process restarts. Do not claim an operation succeeded unless the result says success=true.",
        parameters = {
            type = "object",
            properties = {
                operation = {
                    type = "string",
                    enum = {
                        "create_session",
                        "add_player",
                        "get_state",
                        "get_player",
                        "adjust_bankroll",
                        "set_value",
                        "get_value",
                    },
                    description = "State operation to perform.",
                },
                session_id = {
                    type = "string",
                    description = "Session identifier returned by create_session.",
                },
                name = {
                    type = "string",
                    description = "Session name for create_session or player name for add_player.",
                },
                game_type = {
                    type = "string",
                    description = "Optional session type such as blackjack or dnd; defaults to general.",
                },
                player_id = {
                    type = "string",
                    description = "Player identifier returned by add_player; generated if omitted.",
                },
                bankroll = {
                    type = "number",
                    minimum = 0,
                    description = "Initial bankroll for add_player; defaults to 0.",
                },
                scope = {
                    type = "string",
                    enum = {"session", "player"},
                    description = "Whether set_value/get_value targets session state or a player's state.",
                },
                key = {
                    type = "string",
                    description = "Key for a custom session/player state value.",
                },
                value = {
                    description = "JSON value to store with set_value.",
                },
                amount = {
                    type = "number",
                    description = "Non-zero signed bankroll adjustment. Negative deducts funds; positive adds funds.",
                },
                reason = {
                    type = "string",
                    description = "Optional transaction reason, such as wager, win, loss, or payout.",
                },
            },
            required = {"operation"},
        },
    },
}

return M
