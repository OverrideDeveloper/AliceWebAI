-- Alice Web AI
-- Identity-scoped conversation session storage.
-- Lua 5.1 compatible. This module contains no persistence or request logic.

local Sessions = {}

local function valid_string(value)
    return type(value) == "string" and value ~= ""
end

function Sessions.identity_key(identity)
    if type(identity) ~= "table" then
        return "anonymous:unidentified"
    end

    local provider = identity.provider
    local user_id = identity.id or identity.user_id

    if not valid_string(provider) or not valid_string(user_id) then
        return "anonymous:unidentified"
    end

    return provider .. ":" .. user_id
end

local function record_identity_key(message)
    if type(message) ~= "table"
        or not valid_string(message.user_provider)
        or not valid_string(message.user_id) then
        return nil
    end

    return message.user_provider .. ":" .. message.user_id
end

local function new_session(key, identity)
    return {
        key = key,
        user_id = identity and (identity.id or identity.user_id) or nil,
        user_provider = identity and identity.provider or nil,
        user_name = identity and identity.name or nil,
        history = {},
        overrides = {},
        pending = {},
        busy = false,
    }
end

function Sessions.new(max_messages)
    local store = {
        sessions = {},
        session_order = {},
        legacy_history = {},
        max_messages = max_messages or 128,
        sequence = 0,
        message_order = setmetatable({}, {__mode = "k"}),
    }

    function store:register(message)
        if not self.message_order[message] then
            self.sequence = self.sequence + 1
            self.message_order[message] = self.sequence
        end
    end

    function store:get(identity)
        local key = Sessions.identity_key(identity)
        local session = self.sessions[key]

        if not session then
            session = new_session(key, identity)
            self.sessions[key] = session
            self.session_order[#self.session_order + 1] = key
        elseif identity then
            session.user_id = identity.id or identity.user_id or session.user_id
            session.user_provider = identity.provider or session.user_provider
            session.user_name = identity.name or session.user_name
        end

        return session
    end

    function store:partition(records)
        for _, message in ipairs(records or {}) do
            local key = record_identity_key(message)

            self:register(message)

            if key then
                local session = self.sessions[key]
                if not session then
                    session = new_session(key, {
                        user_id = message.user_id,
                        provider = message.user_provider,
                        name = message.user_name,
                    })
                    self.sessions[key] = session
                    self.session_order[#self.session_order + 1] = key
                end

                session.history[#session.history + 1] = message
            else
                -- Preserve legacy records without exposing them to any user.
                self.legacy_history[#self.legacy_history + 1] = message
            end
        end

        for _, key in ipairs(self.session_order) do
            self:trim(self.sessions[key].history)
        end
    end

    function store:trim(history)
        while #history > self.max_messages do
            table.remove(history, 1)
        end
    end

    function store:flatten()
        local records = {}

        for _, message in ipairs(self.legacy_history) do
            records[#records + 1] = message
        end

        for _, key in ipairs(self.session_order) do
            local session = self.sessions[key]
            for _, message in ipairs(session.history) do
                records[#records + 1] = message
            end
        end

        -- Keep the flat compatibility file and archive in original
        -- cross-user request order, rather than grouping by session.
        table.sort(records, function(left, right)
            return (self.message_order[left] or 0)
                < (self.message_order[right] or 0)
        end)

        return records
    end

    function store:replace(session, records)
        session.history = {}

        for _, message in ipairs(records or {}) do
            if record_identity_key(message) == session.key then
                self:register(message)
                session.history[#session.history + 1] = message
            end
        end

        self:trim(session.history)
    end

    return store
end

return Sessions
