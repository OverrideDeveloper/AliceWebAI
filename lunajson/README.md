# Vendored lunajson

This directory contains the lunajson JSON implementation used by Alice Web AI.

Source:
- https://github.com/OverrideDeveloper/lunajson

The vendored source is kept in-repository so Alice has a reproducible JSON
implementation without relying on LuaRocks, Lit, or another package registry.

The small `../json.lua` adapter preserves Alice's historical decode/encode
return convention while delegating JSON parsing and encoding to lunajson.
