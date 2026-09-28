local webcall = require("../webcall")

local prompt = "webcall> "

local function print_help()
    print("lua-webcall-model interactive CLI")
    print("")
    print("Commands:")
    print("  get <url> [options]               GET a URL")
    print("  post <url> <body> [options]       POST a string body")
    print("  request <method> <url> [options]  Make a parameterized request")
    print("")
    print("Request options:")
    print([[  --header "Name: value"   Add a request header (repeatable)]])
    print([[  --body "text"          Set the request body]])
    print("")
    print("Examples:")
    print([[  request GET https://example.com --header "Accept: application/json"]])
    print([[  request POST https://example.com --header "Content-Type: application/json" --body '{"hello":"world"}']])
    print("")
    print("  help                              Show this help")
    print("  quit                              Exit")
    print("")
end

local function print_response(response, err)
    if err then
        print("error: " .. tostring(err))
    end

    if response then
        print("HTTP " .. tostring(response.status) .. " " .. response.method .. " " .. response.url)
        print("body: " .. tostring(#response.body) .. " bytes")
        print(response.body)
    end

    process.stdin:resume()
    io.write(prompt)
end

local function run_request(options)
    webcall.request(options, print_response)
end

local function tokenize(line)
    local tokens = {}
    local token = {}
    local quote = nil
    local i = 1

    while i <= #line do
        local char = line:sub(i, i)

        if quote then
            if char == quote then
                quote = nil
            elseif char == [[\]] and i < #line then
                i = i + 1
                token[#token + 1] = line:sub(i, i)
            else
                token[#token + 1] = char
            end
        elseif char == '"' or char == "'" then
            quote = char
        elseif char:match("%s") then
            if #token > 0 then
                tokens[#tokens + 1] = table.concat(token)
                token = {}
            end
        elseif char == [[\]] and i < #line then
            i = i + 1
            token[#token + 1] = line:sub(i, i)
        else
            token[#token + 1] = char
        end

        i = i + 1
    end

    if quote then
        return nil, "unterminated quote"
    end

    if #token > 0 then
        tokens[#tokens + 1] = table.concat(token)
    end

    return tokens
end

local function parse_header(value)
    local name, header_value = value:match("^%s*([^:]+)%s*:%s*(.*)$")

    if not name then
        return nil, "header must use 'Name: value' format"
    end

    name = name:match("^%s*(.-)%s*$")
    header_value = header_value:match("^%s*(.-)%s*$")

    if name == "" then
        return nil, "header name cannot be empty"
    end

    return name, header_value
end

local function parse_request_arguments(arguments)
    local method = arguments[1]
    local url = arguments[2]

    if not method or not url then
        return nil, "usage: request <method> <url> [--header \"Name: value\"] [--body \"text\"]"
    end

    local options = {
        method = method:upper(),
        url = url,
        headers = {},
    }

    local i = 3
    while i <= #arguments do
        local parameter = arguments[i]

        if parameter == "--header" then
            local value = arguments[i + 1]
            if not value then
                return nil, "--header requires a value"
            end

            local name, header_value = parse_header(value)
            if not name then
                return nil, header_value
            end

            options.headers[name] = header_value
            i = i + 2
        elseif parameter == "--body" then
            if options.body ~= nil then
                return nil, "--body may only be specified once"
            end

            local value = arguments[i + 1]
            if value == nil then
                return nil, "--body requires a value"
            end

            options.body = value
            i = i + 2
        else
            return nil, "unknown request parameter: " .. parameter
        end
    end

    if next(options.headers) == nil then
        options.headers = nil
    end

    return options
end

local function handle(line)
    line = line:match("^%s*(.-)%s*$")

    if line == "" then
        io.write(prompt)
        return
    end

    local command, rest = line:match("^(%S+)%s*(.*)$")
    command = command:lower()

    if command == "quit" or command == "exit" then
        print("Farewell, webcaller.")
        os.exit(0)
    elseif command == "help" then
        print_help()
        io.write(prompt)
    elseif command == "get" then
        local arguments, tokenize_error = tokenize(rest)
        if not arguments or not arguments[1] then
            print("usage: get <url> [--header \"Name: value\"]")
            io.write(prompt)
        else
            local request_arguments = {"GET"}
            for i = 1, #arguments do
                request_arguments[#request_arguments + 1] = arguments[i]
            end
            local options, parse_error = parse_request_arguments(request_arguments)
            if not options then
                print("error: " .. parse_error)
                io.write(prompt)
            else
                run_request(options)
            end
        end
    elseif command == "post" then
        local arguments, tokenize_error = tokenize(rest)
        if not arguments or not arguments[1] then
            print("usage: post <url> <body> [--header \"Name: value\"]")
            io.write(prompt)
        else
            local request_arguments = {"POST", arguments[1]}
            local start = 2

            if arguments[2] and arguments[2]:sub(1, 2) ~= "--" then
                request_arguments[#request_arguments + 1] = "--body"
                request_arguments[#request_arguments + 1] = arguments[2]
                start = 3
            end

            for i = start, #arguments do
                request_arguments[#request_arguments + 1] = arguments[i]
            end

            local options, parse_error = parse_request_arguments(request_arguments)
            if not options then
                print("error: " .. parse_error)
                io.write(prompt)
            elseif options.body == nil then
                print("error: post requires a body (use --body \"text\")")
                io.write(prompt)
            else
                run_request(options)
            end
        end
    elseif command == "request" then
        local arguments, tokenize_error = tokenize(rest)
        if not arguments then
            print("error: " .. tokenize_error)
            io.write(prompt)
        else
            local options, parse_error = parse_request_arguments(arguments)
            if not options then
                print("error: " .. parse_error)
                io.write(prompt)
            else
                run_request(options)
            end
        end
    else
        print("unknown command: " .. command .. " (try 'help')")
        io.write(prompt)
    end
end

print("lua-webcall-model interactive CLI")
print("Type 'help' for commands or 'quit' to exit.")
io.write(prompt)
process.stdin:resume()

process.stdin:on("data", function(chunk)
    for line in tostring(chunk):gmatch("[^\r\n]+") do
        handle(line)
    end
end)

process.stdin:on("end", function()
    os.exit(0)
end)
