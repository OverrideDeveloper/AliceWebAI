-- Alice Web AI
-- Hacker News top-story tool using the official Firebase API.
-- Lua 5.1 / Luvit compatible.

local json = require("./json")
local webcall = require("./lua-webcall-model/webcall")

local M = {}

local API_ROOT = "https://hacker-news.firebaseio.com/v0"
local REQUEST_TIMEOUT_MS = 10000
local MAX_COUNT = 5
local MAX_STORY_LOOKUPS = 15

local function tool_error(category, message)
    return { category = category, message = message }
end

local function fetch_json(url, callback)
    webcall.get(url, {
        timeout = REQUEST_TIMEOUT_MS,
        headers = {
            ["Accept"] = "application/json",
            ["User-Agent"] = "AliceWebAI/1.0",
        },
    }, function(response, request_error)
        if request_error then
            callback(nil, tostring(request_error))
            return
        end

        if type(response) ~= "table" or type(response.body) ~= "string" then
            callback(nil, "The Hacker News API returned no response body")
            return
        end

        local data, _, decode_error = json.decode(response.body, 1, nil)
        if data == nil then
            callback(nil, "Unable to parse Hacker News JSON: " .. tostring(decode_error))
            return
        end

        callback(data, nil)
    end)
end

local function format_story(story, rank)
    return {
        rank = rank,
        id = story.id,
        title = story.title or "(untitled)",
        author = story.by or "unknown",
        score = tonumber(story.score) or 0,
        comments = tonumber(story.descendants) or 0,
        article_url = type(story.url) == "string" and story.url ~= "" and story.url or nil,
        discussion_url = "https://news.ycombinator.com/item?id=" .. tostring(story.id),
    }
end

function M.get(arguments, callback)
    arguments = arguments or {}
    if type(arguments) ~= "table" then
        callback(nil, tool_error("invalid_request", "Arguments must be an object"))
        return
    end

    local count = tonumber(arguments.count or MAX_COUNT)
    if not count then
        callback(nil, tool_error("invalid_request", "count must be a number"))
        return
    end
    count = math.floor(count)
    if count < 1 then
        callback(nil, tool_error("invalid_request", "count must be at least 1"))
        return
    end
    if count > MAX_COUNT then
        count = MAX_COUNT
    end

    fetch_json(API_ROOT .. "/topstories.json", function(ids, ids_error)
        if ids_error then
            callback(nil, tool_error("upstream_error",
                "Unable to fetch Hacker News top stories: " .. ids_error))
            return
        end
        if type(ids) ~= "table" then
            callback(nil, tool_error("upstream_error",
                "Hacker News returned an invalid top-story list"))
            return
        end

        local stories = {}
        local warnings = {}
        local next_index = 1
        local lookup_limit = math.min(#ids, MAX_STORY_LOOKUPS)

        local function finish()
            if #stories == 0 then
                callback(nil, tool_error("upstream_error",
                    "No Hacker News stories could be retrieved. "
                    .. table.concat(warnings, "; ")))
                return
            end

            callback({
                source = "Hacker News",
                source_url = "https://news.ycombinator.com/",
                requested_count = count,
                returned_count = #stories,
                stories = stories,
                warnings = warnings,
            }, nil)
        end

        local function next_story()
            if #stories >= count or next_index > lookup_limit then
                finish()
                return
            end

            local story_id = ids[next_index]
            next_index = next_index + 1

            if type(story_id) ~= "number" and type(story_id) ~= "string" then
                warnings[#warnings + 1] = "Skipped an invalid story ID"
                next_story()
                return
            end

            fetch_json(API_ROOT .. "/item/" .. tostring(story_id) .. ".json",
                function(story, story_error)
                    if story_error then
                        warnings[#warnings + 1] =
                            "Story " .. tostring(story_id) .. ": " .. story_error
                    elseif type(story) == "table"
                        and story.type == "story"
                        and story.dead ~= true
                        and story.deleted ~= true then
                        stories[#stories + 1] = format_story(story, #stories + 1)
                    end
                    next_story()
                end)
        end

        next_story()
    end)
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "hn_top_news",
        description =
            "Retrieve current top stories from the official Hacker News API. "
            .. "Use this for current technology news or a technology-focused daily briefing. "
            .. "Returns titles, scores, comment counts, article URLs when available, "
            .. "and Hacker News discussion URLs. count defaults to 5 and is capped at 5.",
        parameters = {
            type = "object",
            properties = {
                count = {
                    type = "integer",
                    description = "Number of stories to return, from 1 to 5. Defaults to 5.",
                },
            },
            required = {},
        },
    },
}

M._format_story = format_story

return M
