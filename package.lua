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
return {
  name = "repl-service",
  version = "1.0.0",
  dependencies = {
    "luvit/require",
    "luvit/http",
  },
  optionalDependencies = {
    "luvit/websocket",
  }
}