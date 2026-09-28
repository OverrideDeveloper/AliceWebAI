# lua-webcall-model

A Lua-based abstraction over underlying HTTP calls for interacting with webpages and APIs and returning structured data.

The project is deliberately small and standalone. It provides an HTTP/HTTPS transport boundary that can be used directly from a Lua/Luvit terminal, from scripts, or as a lower-level dependency for larger applications such as AliceWebAI.

## Design

The core abstraction is a request:

```
Lua program
    |
    v
lua-webcall-model
    |
    +-- HTTP
    |
    +-- HTTPS
    |
    v
structured response
```

A web call returns a response object rather than trying to decide what the remote content means.

That distinction is intentional:

- HTTP/HTTPS transport belongs here.
- JSON decoding belongs to a JSON library such as lunajson.
- HTML parsing belongs to a higher-level consumer.
- Search/provider behavior belongs to a higher-level search abstraction.
- AI/tool semantics do not belong here.

This keeps the library useful outside Alice and gives Alice a simple transport seam to consume later.

## Requirements

- Lua running on Luvit
- Luvit's `http` and `https` modules

No AliceWebAI dependency is required.

## Interactive CLI

If you just want to play with the library without building another Lua application, the repository includes a small interactive CLI:

    luvit cli

Then try commands such as `get https://example.com`, `post https://example.com hello`, or `request HEAD https://example.com`. Type `help` for the command list and `quit` to leave.

The CLI is deliberately a thin consumer of the same `webcall` module; it is an entry point for experimentation, not another abstraction layer. Request completion and error paths return control to the prompt so a failed call does not terminate the session.

HTTPS requests automatically use the URL host as the TLS server name (SNI). Callers can override this with `servername` and may pass supported TLS options such as `ca` or `rejectUnauthorized`.

For Luvit's TLS binding, `secureProtocol` is an OpenSSL method name such as `TLS_client`; it is not a TLS version string such as `TLSv1_2`. The library defaults to `TLS_client`, which lets the runtime negotiate the highest supported TLS version. Callers can explicitly override `secureProtocol` when their runtime supports another method name.

## Basic use

```lua
local webcall = require("webcall")

webcall.get("https://example.com", function(response, err)
    if err then
        print("request failed: " .. tostring(err))
        return
    end

    print("status:", response.status)
    print("content length:", #response.body)
    print(response.body)
end)
```

The callback receives:

```lua
response, err
```

On a successful 2xx response, `err` is nil.

The response has this shape:

```lua
{
    status = 200,
    headers = { ... },
    body = "...",
    url = "https://example.com",
    method = "GET",
}
```

Non-2xx HTTP responses still return the response object, with `err` describing the failed status. Transport failures return `nil, err`.

## POST

```lua
local webcall = require("webcall")

webcall.post(
    "https://example.com/api",
    "hello=world",
    {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
        },
    },
    function(response, err)
        if err then
            print("request failed:", err)
            return
        end

        print(response.status)
        print(response.body)
    end
)
```

For JSON APIs, keep JSON encoding/decoding separate:

```lua
local json = require("lunajson")
local webcall = require("webcall")

local payload = json.encode({
    query = "lua",
})

webcall.post(
    "https://example.com/api/search",
    payload,
    {
        headers = {
            ["Content-Type"] = "application/json",
        },
    },
    function(response, err)
        if err then
            print("request failed:", err)
            return
        end

        local data = json.decode(response.body)
        print(data.result)
    end
)
```

## General request API

Convenience methods are provided for GET and POST, but the underlying request model is available directly:

```lua
webcall.request({
    method = "GET",
    url = "https://example.com/resource?limit=10",
    headers = {
        ["Accept"] = "application/json",
    },
    timeout = 10000,
}, function(response, err)
    -- ...
end)
```

Supported request fields:

| Field | Description |
| --- | --- |
| `url` | Absolute `http://` or `https://` URL |
| `method` | HTTP method; defaults to `GET` |
| `headers` | Optional request headers |
| `body` | Optional string request body |
| `timeout` | Optional timeout in milliseconds |
| `servername` | Optional HTTPS TLS server name; defaults to the URL host |
| TLS options | HTTPS options such as `ca`, `cert`, `key`, `pfx`, `ciphers`, and `rejectUnauthorized` |

## What this library does not do

This is intentionally not a web scraper, browser, search engine, JSON framework, or AI interface.

It does not:

- execute JavaScript
- manage cookies or browser sessions
- follow redirects automatically
- parse HTML
- decode JSON automatically
- interpret API-specific response formats
- decide whether retrieved content is trustworthy

Those are useful layers, but they belong above the transport boundary.

## License

MIT. See [LICENSE](LICENSE).
