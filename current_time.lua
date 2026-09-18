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
-- <https://www.gnu.org/licenses/>.
--
-- current_time.lua
-- Lua 5.1 / Luvit compatible.
--
-- Provides Alice with awareness of the current local
-- date and time from the operating system.

local M = {}

function M.current_time(arguments)
    local now = os.date("*t")

    return string.format(
        "%04d-%02d-%02d %02d:%02d:%02d",
        now.year,
        now.month,
        now.day,
        now.hour,
        now.min,
        now.sec
    )
end

M.definition = {
    type = "function",

    ["function"] = {
        name = "current_time",

        description =
            "Get the current local date and time from the operating system. "
            .. "Use this when the user asks what time or date it is, "
            .. "or when current local temporal context is needed.",

        parameters = {
            type = "object",

            properties = {
                unused = {
                    type = "string",
                    description = "Optional. Ignored."
                }
            }
        }
    }
}

return M
