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
--
-- Local development identity provider.
--
-- This module deliberately simulates the identity information that
-- Alice will eventually receive from Cloudflare Access.
--
-- It is NOT an authentication system.
-- It exists only to test identity propagation locally.

local json = require("json")

local Identity = {}

Identity.config = {
    cookie_name = "alice_identity",
}

local identities = {
    mark = {
        user_id = "local-mark",
        name = "Mark",
        email = "mark@local",
        provider = "local",
        authenticated = true,
        anonymous = false,
    },

    test = {
        user_id = "local-test-user",
        name = "Test User",
        email = "test@local",
        provider = "local",
        authenticated = true,
        anonymous = false,
    },

    anonymous = {
        user_id = "local-anonymous",
        name = "Anonymous",
        email = nil,
        provider = "local",
        authenticated = false,
        anonymous = true,
    },
}


local function copy_identity(identity)
    if not identity then
        return nil
    end

    local copy = {}

    for key, value in pairs(identity) do
        copy[key] = value
    end

    return copy
end


function Identity.get_identity(identity_name)
    if not identity_name then
        return nil
    end

    return copy_identity(
        identities[
            tostring(identity_name):lower()
        ]
    )
end


function Identity.get_default()
    return copy_identity(
        identities.anonymous
    )
end


function Identity.list()
    local result = {}

    for name, identity in pairs(identities) do
        result[name] = copy_identity(identity)
    end

    return result
end


function Identity.cookie_value(identity_name)
    local identity =
        Identity.get_identity(identity_name)

    if not identity then
        return nil
    end

    return identity_name
end


function Identity.identity_from_cookie(cookie_value)
    if not cookie_value then
        return nil
    end

    return Identity.get_identity(
        tostring(cookie_value)
    )
end


function Identity.parse_cookie(cookie_header)
    if type(cookie_header) ~= "string" then
        return nil
    end

    for cookie in cookie_header:gmatch(
        "([^;]+)"
    ) do

        local name, value =
            cookie:match(
                "^%s*([^=]+)=([^=]*)%s*$"
            )

        if name ==
            Identity.config.cookie_name then

            return value
        end
    end

    return nil
end


function Identity.from_request(request)
    if type(request) ~= "table" then
        return Identity.get_default()
    end

    local headers =
        request.headers or {}

    local cookie_header =
        headers.cookie or
        headers.Cookie

    local cookie_value =
        Identity.parse_cookie(
            cookie_header
        )

    local identity =
        Identity.identity_from_cookie(
            cookie_value
        )

    if identity then
        return identity
    end

    return Identity.get_default()
end


function Identity.set_cookie_header(identity_name)
    local value =
        Identity.cookie_value(
            identity_name
        )

    if not value then
        return nil
    end

    return string.format(
        "%s=%s; Path=/; HttpOnly; SameSite=Lax",
        Identity.config.cookie_name,
        value
    )
end


function Identity.describe(identity)
    if not identity then
        return "No identity"
    end

    if identity.anonymous then
        return "Anonymous"
    end

    return string.format(
        "%s <%s>",
        tostring(identity.name or "Unknown"),
        tostring(identity.email or "")
    )
end


function Identity.to_json(identity)
    if not identity then
        return "{}"
    end

    local encoded =
        json.encode(identity)

    return encoded or "{}"
end


return Identity
