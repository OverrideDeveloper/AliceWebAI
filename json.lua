-- Alice Web AI JSON compatibility adapter.
-- Alice uses the lunajson implementation vendored under ./lunajson.
-- Keep the historical decode/encode return contract while lunajson
-- remains the actual JSON implementation.

local lunajson = require("./lunajson/lunajson")

local M = {}

function M.decode(text, pos, nullv, arraylen)
    local ok, value, next_pos = pcall(
        lunajson.decode,
        text,
        pos,
        nullv,
        arraylen
    )

    if not ok then
        return nil, nil, value
    end

    return value, next_pos, nil
end

function M.encode(value, _options)
    local ok, encoded = pcall(
        lunajson.encode,
        value
    )

    if not ok then
        return nil, encoded
    end

    return encoded, nil
end

return M
