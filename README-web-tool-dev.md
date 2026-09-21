# AliceWebAI web-tool-dev architecture notes

This branch establishes the first middleware foundations for Internet search, observability, evidence provenance, policy, authoritative state, and response post-processing.

## Tool boundary

The Alice web_search tool is an adapter over the standalone OverrideDeveloper/lua-web-search module.

The search engine module owns provider-specific retrieval and normalization. Alice owns tool policy, evidence capture, and model-facing serialization.

The current Alice adapter configures the DuckDuckGo provider. Future providers, including a local Wikipedia corpus, can be added without changing the Alice tool loop.

Search results are returned with:
- query
- engine
- title
- URL
- snippet
- retrieved evidence metadata

Search results are evidence, not independently verified facts.

## Search provider outcomes

The search layer distinguishes provider outcomes from an empty result set. An automated-access challenge, network failure, HTTP failure, and successfully parsed zero-result response are different observations.

## Identity

Alice now distinguishes:
- verified identity
- authenticated/asserted identity
- anonymous identity

The current local identity provider remains a development identity provider. It should not be treated as production authentication.

## Human agency

authoritative_state.lua provides a generic state container for future stateful workflows. A state can explicitly require a human action before it may advance. This is intended to become the common invariant for games and other workflows where the model must not cross a human decision point.

## Observability

observability.lua gives requests and tool rounds correlation IDs and structured error categories instead of collapsing every failure into one message.

## Epistemic status

evidence.lua and response_policy.lua distinguish retrieved evidence from model-only output. The model's existing certainty marker is inspected but not treated as authoritative.

## Memory

The existing memory tools remain available. Future work should make memory writes explicitly policy-aware using user_requested or durable intent metadata rather than allowing arbitrary model persistence.

## Multi-user isolation

The existing conversation history is still process-global. This branch does not pretend that has been solved; the request IDs and identity metadata make the boundary visible so session isolation can be implemented next.

## State transitions

Future game implementations should keep authoritative state outside the LLM: deck, hands, stacks, pot, turn, phase, wagers, and random results. The model should narrate that state rather than invent it.

## Epistemic response pipeline

Responses are inspected as candidate claims rather than assigned one global certainty score. Each candidate claim is represented with a provenance status such as retrieved or constructed; retrieved claims may carry URLs from actual web-search events. Freshness-sensitive language is flagged when no current web evidence event exists, and claims of external verification are flagged when no matching provenance event exists.

The response policy also emits source URLs from actual retrieval events so provenance is navigable rather than merely asserted.

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

## Epi-logic development branch

epi-logic-dev extends the web-tool foundations with:
- end-to-end web evidence metadata from tool execution into response inspection
- removal of the global Certainty Level prompt contract
- detection of unsupported claims of external verification
- source URL emission from actual retrieved evidence
- freshness-gap detection for today, now, latest, and current language
- a dedicated max_tool_rounds_exceeded observability category
- candidate claim-level provenance objects distinguishing retrieved claims from model construction
