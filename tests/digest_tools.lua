-- Alice Web AI
-- Regression tests for daily-briefing tool helpers and definitions.
-- Lua 5.1 / Luvit compatible.

local HNTopNews = require("../hn_top_news")
local LocalWeather = require("../local_weather")

assert(HNTopNews.definition["function"].name == "hn_top_news")
assert(LocalWeather.definition["function"].name == "local_weather")

local story = HNTopNews._format_story({
    id = 123,
    title = "Example headline",
    by = "alice",
    score = 42,
    descendants = 7,
    url = "https://example.com/story",
}, 1)

assert(story.rank == 1)
assert(story.title == "Example headline")
assert(story.score == 42)
assert(story.comments == 7)
assert(story.article_url == "https://example.com/story")
assert(story.discussion_url == "https://news.ycombinator.com/item?id=123")

assert(LocalWeather._url_encode("Juneau, Alaska") == "Juneau%2C%20Alaska")
assert(LocalWeather._url_encode("New York") == "New%20York")
assert(LocalWeather._weather_description(0) == "Clear sky")
assert(LocalWeather._weather_description("61") == "Slight rain")
assert(LocalWeather._weather_description(999) == "Unknown conditions")

print("digest_tools.lua tests passed")
