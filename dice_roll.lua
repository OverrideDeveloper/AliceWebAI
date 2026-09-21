-- Alice Web AI

-- Copyright (C) 2026 Override Development

-- This file is part of Alice Web AI.

-- Alice Web AI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--------------------------------------

-- Alice Web AI is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
-----------------------------------------------

-- You should have received a copy of the GNU General Public License
-- along with Alice Web AI. If not, see
-- https://www.gnu.org/licenses/.

-- dice_roll.lua
-- Lua 5.1 compatible

local M = {}

local random_seeded = false

local function seed_random()
    if not random_seeded then
        math.randomseed(os.time())
        math.random()
        math.random()
        math.random()

        random_seeded = true
    end
end

local function parse_dice_expression(expression)
    if type(expression) ~= "string" or expression == "" then
        return nil, "expression is required"
    end

    expression = expression:lower():gsub("%s+", "")

    local count, sides, modifier =
        expression:match("^(%d*)d(%d+)([+-]%d+)$")

    if not count then
        count, sides = expression:match("^(%d*)d(%d+)$")
    end

    if not sides then
        return nil,
            "invalid dice expression; use formats such as d20, 1d20, 2d6, or 1d20+5"
    end

    count = tonumber(count)

    if not count or count == 0 then
        count = 1
    end

    sides = tonumber(sides)
    modifier = tonumber(modifier) or 0

    if count < 1 or count > 100 then
        return nil, "number of dice must be between 1 and 100"
    end

    if sides < 2 or sides > 1000 then
        return nil, "die size must be between 2 and 1000"
    end

    if modifier < -10000 or modifier > 10000 then
        return nil, "modifier must be between -10000 and 10000"
    end

    return {
        expression = expression,
        count = count,
        sides = sides,
        modifier = modifier
    }
end


function M.dice_roll(arguments)
    if type(arguments) ~= "table" then
        return "Error: arguments must be an object"
    end

    local dice, err = parse_dice_expression(arguments.expression)

    if not dice then
        return "Error: " .. err
    end

    seed_random()

    local total = dice.modifier
    local rolls = {}

    for i = 1, dice.count do
        local roll = math.random(1, dice.sides)
        rolls[#rolls + 1] = roll
        total = total + roll
    end

    if arguments.individual == true then
        return {
            expression = dice.expression,
            rolls = rolls,
            total = total,
        }
    end

    return tostring(total)
end



M.definition = {
    type = "function",
    ["function"] = {
        name = "dice_roll",
        description =
        "Roll tabletop dice and return the numeric total. " ..
        "You MUST use this tool whenever a random result is needed. " ..
        "Never invent a roll.",
        parameters = {
            type = "object",
            properties = {
                expression = {
                    type = "string",
                    description =
                        "Dice expression such as d20, 2d6, or 1d20+5"
                },
                reason = {
                    type = "string",
                    description =
                        "What the roll determines, such as Perception check"
                },
                individual = {
                    type = "boolean",
                    description =
                        "Return each individual die result as well as the total."
                }
            },
            required = {
                "expression",
                "reason"
            }
        }
    }
}


return M
