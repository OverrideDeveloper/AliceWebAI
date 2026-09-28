local webcall = require("webcall")

webcall.get("https://example.com", function(response, err)
    if err then
        print("request failed: " .. tostring(err))
        return
    end

    print("HTTP " .. tostring(response.status))
    print("URL: " .. response.url)
    print(response.body)
end)
