-- Alice Web AI
-- Current weather and forecast tool using Open-Meteo APIs.
-- Lua 5.1 / Luvit compatible.

local json = require("./json")
local webcall = require("./lua-webcall-model/webcall")

local M = {}

local REQUEST_TIMEOUT_MS = 10000

local WEATHER_CODES = {
    [0] = "Clear sky",
    [1] = "Mainly clear",
    [2] = "Partly cloudy",
    [3] = "Overcast",
    [45] = "Fog",
    [48] = "Depositing rime fog",
    [51] = "Light drizzle",
    [53] = "Moderate drizzle",
    [55] = "Dense drizzle",
    [56] = "Light freezing drizzle",
    [57] = "Dense freezing drizzle",
    [61] = "Slight rain",
    [63] = "Moderate rain",
    [65] = "Heavy rain",
    [66] = "Light freezing rain",
    [67] = "Heavy freezing rain",
    [71] = "Slight snow",
    [73] = "Moderate snow",
    [75] = "Heavy snow",
    [77] = "Snow grains",
    [80] = "Slight rain showers",
    [81] = "Moderate rain showers",
    [82] = "Violent rain showers",
    [85] = "Slight snow showers",
    [86] = "Heavy snow showers",
    [95] = "Thunderstorm",
    [96] = "Thunderstorm with slight hail",
    [99] = "Thunderstorm with heavy hail",
}

local function tool_error(category, message)
    return { category = category, message = message }
end

local function url_encode(value)
    value = tostring(value or "")
    return (value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function weather_description(code)
    return WEATHER_CODES[tonumber(code)] or "Unknown conditions"
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
            callback(nil, "The weather API returned no response body")
            return
        end

        local data, _, decode_error = json.decode(response.body, 1, nil)
        if data == nil then
            callback(nil, "Unable to parse weather JSON: " .. tostring(decode_error))
            return
        end

        if type(data) ~= "table" then
            callback(nil, "The weather API returned an invalid JSON object")
            return
        end

        if data.error then
            callback(nil, tostring(data.reason or "The weather API returned an error"))
            return
        end

        callback(data, nil)
    end)
end

local function valid_number(value)
    return type(value) == "number" and value == value
end

function M.get(arguments, callback)
    arguments = arguments or {}
    if type(arguments) ~= "table" then
        callback(nil, tool_error("invalid_request", "Arguments must be an object"))
        return
    end

    local location = arguments.location
    if type(location) ~= "string" or location:match("^%s*$") then
        callback(nil, tool_error("invalid_request", "location is required"))
        return
    end

    local temperature_unit = tostring(arguments.temperature_unit or "fahrenheit"):lower()
    if temperature_unit ~= "fahrenheit" and temperature_unit ~= "celsius" then
        callback(nil, tool_error("invalid_request",
            "temperature_unit must be fahrenheit or celsius"))
        return
    end

    local forecast_days = tonumber(arguments.forecast_days or 5)
    if not forecast_days then
        callback(nil, tool_error("invalid_request", "forecast_days must be a number"))
        return
    end
    forecast_days = math.floor(forecast_days)
    if forecast_days < 1 or forecast_days > 7 then
        callback(nil, tool_error("invalid_request",
            "forecast_days must be between 1 and 7"))
        return
    end

    local geocode_url =
        "https://geocoding-api.open-meteo.com/v1/search"
        .. "?name=" .. url_encode(location)
        .. "&count=1&language=en&format=json"

    fetch_json(geocode_url, function(geocode, geocode_error)
        if geocode_error then
            callback(nil, tool_error("upstream_error",
                "Unable to find weather location: " .. geocode_error))
            return
        end

        if type(geocode.results) ~= "table" or #geocode.results == 0 then
            callback(nil, tool_error("location_not_found",
                "Location not found: " .. location))
            return
        end

        local place = geocode.results[1]
        if type(place) ~= "table"
            or not valid_number(place.latitude)
            or not valid_number(place.longitude) then
            callback(nil, tool_error("upstream_error",
                "Geocoding result did not contain valid coordinates"))
            return
        end

        local unit_symbol = temperature_unit == "celsius" and "°C" or "°F"
        local forecast_url =
            "https://api.open-meteo.com/v1/forecast"
            .. "?latitude=" .. tostring(place.latitude)
            .. "&longitude=" .. tostring(place.longitude)
            .. "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            .. "&forecast_days=" .. tostring(forecast_days)
            .. "&temperature_unit=" .. temperature_unit
            .. "&wind_speed_unit=kmh&timezone=auto"

        fetch_json(forecast_url, function(data, weather_error)
            if weather_error then
                callback(nil, tool_error("upstream_error",
                    "Unable to retrieve weather forecast: " .. weather_error))
                return
            end

            local current = data.current
            local daily = data.daily
            if type(current) ~= "table"
                or type(daily) ~= "table"
                or type(daily.time) ~= "table" then
                callback(nil, tool_error("upstream_error",
                    "Weather response is missing current or daily forecast data"))
                return
            end

            local place_name = tostring(place.name or location)
            if type(place.admin1) == "string" and place.admin1 ~= "" then
                place_name = place_name .. ", " .. place.admin1
            end
            if type(place.country) == "string" and place.country ~= "" then
                place_name = place_name .. ", " .. place.country
            end

            local forecast = {}
            for index, date in ipairs(daily.time) do
                forecast[#forecast + 1] = {
                    date = date,
                    conditions = weather_description(
                        daily.weather_code and daily.weather_code[index]),
                    high = daily.temperature_2m_max and daily.temperature_2m_max[index] or nil,
                    low = daily.temperature_2m_min and daily.temperature_2m_min[index] or nil,
                    precipitation_probability = daily.precipitation_probability_max
                        and daily.precipitation_probability_max[index] or nil,
                }
            end

            callback({
                source = "Open-Meteo",
                source_url = "https://open-meteo.com/",
                location = {
                    requested = location,
                    name = place_name,
                    latitude = place.latitude,
                    longitude = place.longitude,
                    timezone = data.timezone or place.timezone,
                },
                units = {
                    temperature = unit_symbol,
                    wind_speed = "km/h",
                    precipitation_probability = "%",
                },
                current = {
                    time = current.time,
                    conditions = weather_description(current.weather_code),
                    temperature = current.temperature_2m,
                    feels_like = current.apparent_temperature,
                    relative_humidity = current.relative_humidity_2m,
                    wind_speed = current.wind_speed_10m,
                },
                forecast = forecast,
            }, nil)
        end)
    end)
end

M.definition = {
    type = "function",
    ["function"] = {
        name = "local_weather",
        description =
            "Get current weather conditions and a 1–7 day forecast for a named location "
            .. "using Open-Meteo. Use this for a daily briefing or weather question. "
            .. "Returns the resolved place, current conditions, daily highs/lows, "
            .. "precipitation probabilities, units, and source URL. Defaults to Fahrenheit "
            .. "and five forecast days.",
        parameters = {
            type = "object",
            properties = {
                location = {
                    type = "string",
                    description = "City, postal code, or place, such as 'Juneau, Alaska'.",
                },
                temperature_unit = {
                    type = "string",
                    enum = {"fahrenheit", "celsius"},
                    description = "Temperature unit. Defaults to fahrenheit.",
                },
                forecast_days = {
                    type = "integer",
                    description = "Number of forecast days from 1 to 7. Defaults to 5.",
                },
            },
            required = {"location"},
        },
    },
}

M._url_encode = url_encode
M._weather_description = weather_description

return M
