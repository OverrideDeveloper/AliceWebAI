# CLI

The CLI is the deliberately boring front door for experimenting with lua-webcall-model without needing another Lua application.

From the repository root, run:

    luvit cli

Then:

    lua-webcall-model interactive CLI
    Type 'help' for commands or 'quit' to exit.
    webcall> get https://example.com

Available commands:

- get <url>
- post <url> <body>
- request <method> <url> [options]
- help
- quit

Parameterized requests support repeatable headers and an optional body:

    request GET https://example.com --header "Accept: application/json"
    request POST https://example.com --header "Content-Type: application/json" --body '{"hello":"world"}'

The CLI parses these parameters into the existing webcall.lua request options. It does not implement a second HTTP layer.

The CLI is intentionally a thin consumer of webcall.lua. It is not part of the transport abstraction itself.
