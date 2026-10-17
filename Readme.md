# AliceWebAI

AliceWebAI is a local, model-independent AI runtime. Alice's Lua middleware sits between the human-facing interface and the language model, coordinating conversation state, tool execution, behavioral policy, and execution provenance.

> Alice gives an LLM model an operating environment, with provenance as a first-class property of that environment.

## Why Alice Exists

Alice began on September 4, 2026, after an AI model repeatedly denied receiving a prompt until presented with a screenshot.

That frustrated me enough to take a look at what I'd picked up over more than a decade of IT Systems Engineering focused on integrating disparate systems and ask myself:

What happens if I put a tool between the human and the model? A tool designed to give humans better agency.

Thus, Alice was created.

And no, the name isn't a technology reference. It's a Lewis Carroll reference.

## Architecture

The Windows runtime brings together these local components:

```text
Browser
  |
  v
Luvit web_server.lua :8080
  |
  v
Alice Lua middleware
  |-----------------------|
  |           |           |
  v           v           v
llm_client  Memory tools  Local evidence tools
  |           |           |
  v           v           v
llama.cpp   Python        Rust Data Engine
:50006      memory        :60005
             service
             :8090
               |
               v
            ChromaDB
```

- **Alice / Lua / Luvit** owns the browser interface, conversation lifecycle, tool orchestration, request boundaries, cancellation, and tool-execution provenance.
- **llama.cpp** runs local model inference through its OpenAI-compatible chat-completions API. Alice uses the vendored `lua-llama-interface` boundary.
- **The Python memory service** provides local HTTP access to ChromaDB. Semantic memory is separate from conversation history.
- **The Rust Data Engine** prepares and searches a selected local corpus and returns bounded evidence.
- **Web search** uses a provider boundary with DuckDuckGo HTML and Mojeek fallback. Provider failure is distinguished from a successful search with no results.

Services bind to loopback by default. This is a local runtime, not a claim that the application is hardened for exposure to an untrusted network.

## Repository layout

```text
AliceWebAI/
├── alice.lua                 # Alice runtime and tool orchestration
├── llm_client.lua            # Inference and tool-call integration
├── deck_draw.lua              # Stateful card, rune, and I Ching draws
├── web_server.lua            # Browser interface server
├── index.html                # Chat UI
├── memory_service.py         # HTTP service for semantic memory
├── chroma_memory.py          # ChromaDB storage operations
├── memory_client.lua         # Lua-to-memory-service client
├── memory_store.lua          # Memory storage tool
├── memory_search.lua         # Memory search tool
├── evidence_corpus.lua       # Discover active evidence corpus
├── task_manager.lua          # Sequential batch tool orchestration
├── hn_top_news.lua            # Hacker News top-story API tool
├── local_weather.lua          # Open-Meteo current weather and forecast
├── evidence_hunt.lua         # Search for relevant records
├── evidence_gather.lua       # Retrieve bounded evidence
├── web_search.lua            # Web-search provider boundary
├── lua-llama-interface/      # Vendored inference interface/backend
├── lua-webcall-model/        # Vendored HTTP transport abstraction
├── lua-web-search/           # Vendored search implementation
├── controller/start.ps1      # Windows runtime controller
├── model/                    # Local GGUF model
├── corpus/                   # Local corpus inputs
├── bin/                      # Runtime executables
└── logs/                     # Controller logs
```

Model files and corpus datasets are local assets and should not be committed to the repository.

## Requirements

The documented runtime workflow is for Windows and uses the controller.

- PowerShell
- Lua 5.1 and Luvit available on `PATH`
- Python and ChromaDB (a project-local `.venv` is recommended)
- llama.cpp's `llama-server.exe`
- One compatible `.gguf` model in `model\`
- For local evidence, the Rust Data Engine executable, `dataset-stream-parser-api.exe`, and a supported corpus input in `corpus\`

No Ollama installation is required.

## Setup and startup

1. Clone the repository and enter its directory:

   ```powershell
   git clone https://github.com/OverrideDeveloper/AliceWebAI.git
   Set-Location AliceWebAI
   ```

2. Install Lua 5.1, Luvit, Python, and llama.cpp. Make `lua` and `luvit` available on `PATH`.

3. Create the Python environment and install ChromaDB:

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install --upgrade pip
   .\.venv\Scripts\python.exe -m pip install chromadb
   ```

4. Put `llama-server.exe` in `bin\` or make it available on `PATH`. Put exactly one compatible GGUF model in `model\`.

5. To enable local evidence, build `dataset-stream-parser-api.exe` from the companion repository and place it in `bin\`. Put an XML/XML.BZ2 corpus file or a subdirectory of text files in `corpus\`. The controller can also run without local evidence.

6. From the repository root, start Alice:

   ```powershell
   .\controller\start.ps1
   ```

The controller checks prerequisites and port conflicts, selects the model and optional corpus, starts the services, and reports readiness. It keeps the Alice web-server console visible separately from the controller's own output. Logs for redirected service output are written under `logs\`.

Open [http://127.0.0.1:8080/](http://127.0.0.1:8080/) when Alice reports ready.

The controller selects one corpus per run. For multiple corpus candidates, it asks which one to load. Corpus preparation may take a while; the evidence API becomes ready when preparation finishes, independently of the other services.

### Local endpoints

| Service | Address |
|---|---|
| Alice web interface | `http://127.0.0.1:8080/` |
| llama.cpp inference | `http://127.0.0.1:50006/` |
| Memory service | `http://127.0.0.1:8090/memory/status` |
| Rust Data Engine | `http://127.0.0.1:60005/local_data/status` |

## Alice's tools and evidence

The available tools include:

- `current_time` — retrieve the current time.
- `dice_roll` — roll dice, optionally returning individual rolls.
- `deck_draw` — draw playing cards, tarot cards, Elder Futhark runes, or I Ching hexagrams without replacement; each used deck keeps its state in the running server and automatically reshuffles on exhaustion.
- `memory_store` and `memory_search` — store and search semantic memories.
- `web_search` — search the web through the configured provider boundary.
- `EvidenceCorpus` — discover the active corpus identifier.
- `EvidenceHunt` — search for records relevant to a term or query.
- `EvidenceGather` — retrieve bounded evidence from selected records.
- `task_manager` — execute up to eight existing tools sequentially and return each result or structured failure; later calls continue after a failure.
- `hn_top_news` — retrieve up to five current top stories from the official Hacker News API, including article and discussion URLs.
- `local_weather` — retrieve current conditions and a 1–7 day forecast from Open-Meteo for a named location, with Fahrenheit or Celsius temperatures.

The daily-briefing tools use the asynchronous `lua-webcall-model` transport and Alice's `lunajson`-backed JSON adapter; they do not shell out to `curl`. Hacker News results retain article and discussion URLs, and weather results include the selected geocoded place and forecast units.

The local evidence workflow separates finding a relevant record from retrieving its content. Alice discovers the configured corpus through the Rust API instead of assuming a corpus name. Evidence returned to the model is bounded.

`task_manager` accepts a fixed, ordered list of tool names and arguments. It returns a per-call status, arguments, result or structured error, and records nested calls in execution provenance. Calls continue after an individual failure. This first version does not pass one tool result into later call arguments; Alice must provide every call's arguments up front.

A model's tool-call request is not proof that a tool succeeded. Alice executes the tool and handles its result; failures remain distinguishable from successful empty results.

## Conversation history and semantic memory

Conversation history is stored in `conversation_history.json`. ChromaDB-backed semantic memory is stored separately under `memory/chroma`.

- Conversation history preserves the conversational exchange.
- Semantic memory stores selected information for later retrieval.
- Lua memory tools communicate with the Python memory service through `memory_client.lua`.

ChromaDB may initialize or download embedding assets during the first memory operation.

## Request boundaries and provenance

Each incoming human message starts a new request. Conversation history supplies context; it does not authorize Alice to resume old tool work.

- Tool execution belongs to the current request.
- A failed or tool-limited request is terminal once Alice reports the failure.
- A retry or continuation must be established by the current message.
- Request IDs and terminal request state help separate current execution from stale asynchronous work.
- The Lua response layer can add a concise **Tools executed** section that distinguishes successful and failed calls.

Observability records request boundaries, model-round decisions, tool calls, and terminal outcomes. These are execution records, not model reasoning or chain-of-thought.

The design goal is traceable provenance across discovery, retrieval, execution, and presentation.

## Web search behavior

The current provider pool is DuckDuckGo HTML with capacity for more to be added.

- An access challenge, HTTP failure, timeout, or unusable response is a provider failure—not a successful search with zero results.
- A successful search with no matching results is a valid empty result.
- Search attempts are bounded per request, and duplicate normalized queries are rejected.
- Provider failure must not be treated as evidence that a subject does not exist.

## Tests

Regression tests cover request boundaries, response policy, and web-search behavior:

```text
tests/request_boundary.lua
tests/response_policy.lua
tests/web_search.lua
tests/task_manager.lua
tests/deck_draw.lua
tests/digest_tools.lua
```

## Troubleshooting

- **Alice does not open:** Check the controller output and confirm that the Alice service reports ready.
- **A port is already in use:** Stop the existing service using that port, then start the controller again.
- **Memory or inference fails to start:** Check the relevant service output under `logs\\` and confirm its dependencies and model are present.
- **Evidence is not ready yet:** Large corpus preparation takes time. Check the evidence log for progress or errors.

## License

AliceWebAI is licensed under the GNU General Public License v3.0 or later. See `LICENSE.txt` for the license text.

## Author

Override Development
