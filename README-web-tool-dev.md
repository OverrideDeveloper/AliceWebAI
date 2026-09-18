# AliceWebAI web-tool-dev architecture notes

This branch establishes the first middleware foundations for Internet search,
observability, evidence provenance, policy, authoritative state, and response
post-processing.

## Tool boundary

The default web search provider is DuckDuckGo's non-JavaScript HTML search.
The provider is isolated in `web_search.lua` so it can later be replaced by
an API-backed provider without changing Alice's tool loop.

Search results are returned with:
- query
- engine
- title
- URL
- snippet
- retrieved evidence metadata

Search results are evidence, not independently verified facts.

## Identity

Alice now distinguishes:
- verified identity
- authenticated/asserted identity
- anonymous identity

The current local identity provider remains a development identity provider.
It should not be treated as production authentication.

## Human agency

`authoritative_state.lua` provides a generic state container for future
stateful workflows. A state can explicitly require a human action before it
may advance. This is intended to become the common invariant for games and
other workflows where the model must not cross a human decision point.

## Observability

`observability.lua` gives requests and tool rounds correlation IDs and
structured error categories instead of collapsing every failure into one
message.

## Epistemic status

`evidence.lua` and `response_policy.lua` distinguish retrieved evidence
from model-only output. The model's existing certainty marker is inspected
but not treated as authoritative.

## Memory

The existing memory tools remain available. Future work should make memory
writes explicitly policy-aware using `user_requested` or `durable` intent
metadata rather than allowing arbitrary model persistence.

## Multi-user isolation

The existing conversation history is still process-global. This branch
does not pretend that has been solved; the request IDs and identity metadata
make the boundary visible so session isolation can be implemented next.

## State transitions

Future game implementations should keep authoritative state outside the LLM:
deck, hands, stacks, pot, turn, phase, wagers, and random results. The model
should narrate that state rather than invent it.

## Evidence flow

The intended pipeline is:

Human
  -> Alice policy
  -> LLM
  -> Alice tool execution
  -> authoritative/retrieved evidence
  -> LLM
  -> Alice response inspection
  -> Human
