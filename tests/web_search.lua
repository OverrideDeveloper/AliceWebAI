-- Alice Web AI
-- Regression tests for web search response classification and parsing.
-- Lua 5.1 compatible.

local WebSearch = require("../web_search")

local challenge = [[
<div class="anomaly-modal__title">Unfortunately, bots use DuckDuckGo too.</div>
<div class="anomaly-modal__description">Please complete the following challenge to confirm this search was made by a human.</div>
]]

assert(
    WebSearch._classify_response("DuckDuckGo", challenge)
        == "access_challenge",
    "DuckDuckGo access challenge must not be treated as a search page"
)

local duckduckgo = [[
<div class="result results_links_deep web-result">
  <a class="result__a" href="https://example.com/story">Example Story</a>
  <a class="result__snippet" href="https://example.com/story">Example snippet</a>
</div></div>
]]

local ddg_results =
    WebSearch._parse_results(
        duckduckgo,
        5,
        "DuckDuckGo"
    )

assert(#ddg_results == 1, "DuckDuckGo result parser should find one result")
assert(ddg_results[1].url == "https://example.com/story")
assert(ddg_results[1].title == "Example Story")

local mojeek = [[
<ul class="results-standard">
  <li class="result">
    <h2><a href="https://example.org/story">Mojeek Story</a></h2>
    <p class="s">Mojeek snippet</p>
  </li>
</ul>
]]

local mojeek_results =
    WebSearch._parse_results(
        mojeek,
        5,
        "Mojeek"
    )

assert(#mojeek_results == 1, "Mojeek result parser should find one result")
assert(mojeek_results[1].url == "https://example.org/story")
assert(mojeek_results[1].title == "Mojeek Story")

print("web_search.lua tests passed")
