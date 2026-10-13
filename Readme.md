# AliceWebAI

AliceWebAI is a local, model-independent AI runtime. Alice's Lua middleware sits between the human-facing interface and the language model, coordinating conversation state, tool execution, behavioral policy, and execution provenance.

Alice is named for Lewis Carroll's Alice, not for a particular technology.

> Alice gives an LLM model an operating environment, with provenance as a first-class property of that environment.

The intent is to give the operator agency and visibility: what Alice did, which tools ran, what inputs were supplied, and which results support a response should remain part of the application environment—not something the model has to remember to report accurately.

## Current architecture

The Windows development runtime currently uses a local llama.cpp server rather than requiring Ollama.

```text
Browser
  |
  | HTTP :8080
  v
Luvit web_server.lua
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

- **Alice / Lua / Luvit** owns the web interface, conversation lifecycle, tool loop, policy, cancellation, and tool-execution provenance.
- **llama.cpp** performs local model inference through its OpenAI-compatible chat-completions API. Alice talks to it through the vendored `lua-llama-interface` boundary.
- **The Python memory service** exposes local HTTP endpoints backed by ChromaDB. Conversation history and semantic memory are separate stores.
- **The Rust Data Engine** prepares and searches a selected local corpus, then returns indexed records or bounded evidence fragments to Alice.
- **Web search** is a provider abstraction with DuckDuckGo HTML and Mojeek fallback. Provider failure is distinct from a successful search that returned no results.

All configured service endpoints bind to loopback by default. This is a local development setup, not a claim that the application is hardened for exposure to an untrusted network.

## Repository layout

```text
AliceWebAI/
├── alice.lua                 # Alice runtime and tool orchestration
├── llm_client.lua            # Inference and tool-call integration
├── web_server.lua            # Local browser interface server
├── index.html                # Chat UI
├── memory_service.py         # HTTP service for semantic memory
├── chroma_memory.py          # ChromaDB storage operations
├── memory_client.lua         # Lua-to-memory-service client
├── memory_store.lua          # Memory storage tool
├── memory_search.lua         # Memory search tool
├── evidence_corpus.lua       # Discover active evidence corpus
├── evidence_hunt.lua         # Search for relevant records
├── evidence_gather.lua       # Retrieve bounded evidence
├── web_search.lua            # Web-search provider boundary
├── lua-llama-interface/      # Vendored inference interface/backend
├── lua-webcall-model/        # Vendored HTTP transport abstraction
├── lua-web-search/           # Vendored search implementation
├── controller/start.ps1      # Windows runtime launcher
├── model/                    # Place one local .gguf model here
├── corpus/                   # Place local corpus inputs here
├── bin/                      # Runtime executables (not necessarily committed)
└── logs/                     # Controller logs
```

The exact contents of `bin/`, `model/`, and `corpus/` depend on the local installation. Large model files and corpus datasets are local assets, not source files to commit.

## Requirements

The current controller and manual startup workflow are primarily documented for Windows.

- **Luvit** available as `luvit` on `PATH`.
- **Lua 5.1** available as `lua` on `PATH` for the controller's prerequisite check.
- **Python** and the `chromadb` package, preferably in the project-local `.venv`.
- **llama.cpp** with `llama-server.exe`.
- One compatible local GGUF model.
- For local corpus evidence, the built Rust Data Engine executable, `dataset-stream-parser-api.exe`, and a supported corpus input.
- Git, if cloning or updating the repository.

No Ollama installation is required for the current llama.cpp-backed runtime.

## Setup

### 1. Obtain the project

Clone the repository and enter its root directory:

```powershell
git clone https://github.com/OverrideDeveloper/AliceWebAI.git
Set-Location AliceWebAI
```

If you are using a development branch, check out that branch before continuing.

### 2. Install Luvit and Lua

Install Lua 5.1 and Luvit for your environment. Confirm that both commands resolve:

```powershell
lua -v
luvit --version
```

The web server is launched with Luvit, not with the standalone Lua interpreter.

### 3. Prepare Python memory dependencies

Create a virtual environment and install ChromaDB:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install chromadb
```

The controller prefers `.venv\Scripts\python.exe` when it exists and checks that it can import `chromadb`.

Note: `requirements.txt` currently describes the separate Discord adapter dependencies; it does not replace the ChromaDB installation above.

ChromaDB may initialize or download embedding assets on first use, so the first memory operation can take longer than subsequent ones.

### 4. Install llama.cpp and a model

Place `llama-server.exe` in `bin\`, or make it available on `PATH`.

Place **one** compatible `.gguf` model in `model\`. The current Windows controller expects exactly one GGUF file in that folder so it can choose the model unambiguously.

The default inference configuration is:

- Host: `127.0.0.1`
- Port: `50006`
- Context size: `8192`
- Chat completions endpoint: `/v1/chat/completions`

These values are configured in Alice's `llm_client.lua` and `controller/start.ps1`; keep them aligned if you change them.

### 5. Prepare local evidence (optional)

To enable local corpus evidence, build the Rust API executable from the companion repository:

`https://github.com/OverrideDeveloper/dataset-stream-parser-interface`

Build it for Windows using that repository's API manifest, then copy the resulting `dataset-stream-parser-api.exe` into Alice's `bin\` directory.

Put a corpus input under `corpus\`:

- An XML file, such as a Wikipedia dump.
- An `.xml.bz2` file supported by the engine.
- A subdirectory containing a collection of text files.

If more than one candidate is found, the controller asks which one to load. It derives a corpus identifier from the selected filename or folder name; names containing `wiki` are normalized to `wikipedia`.

The controller starts one Rust Data Engine process for the selected corpus with preparation enabled. Preparation can take a long time for large datasets. The API may not listen until preparation has completed, while Alice, memory, and inference can start independently.

If you do not want local evidence for a run, the controller can be asked to start without a corpus. The evidence tools will not have a usable corpus in that case.

The Rust API exposes `GET /local_data/corpus`, returning the configured corpus identifier as JSON, for example:

```json
{"corpus":"wikipedia"}
```

Alice's `EvidenceCorpus` tool uses this endpoint so evidence tools can discover the active corpus rather than hardcoding its name.

## Starting Alice

### Option A: Windows controller

From the repository root:

```powershell
.\controller\start.ps1
```

The controller checks prerequisites and port conflicts, selects the model and optional corpus, starts the configured services, and monitors their readiness. It writes service logs beneath `logs\` and stops the processes it started when the controller exits.

The expected local endpoints are:

| Service | Address |
|---|---|
| Alice web interface | `http://127.0.0.1:8080/` |
| llama.cpp inference | `http://127.0.0.1:50006/` |
| Memory service | `http://127.0.0.1:8090/memory/status` |
| Rust Data Engine | `http://127.0.0.1:60005/local_data/status` |

The evidence service is optional. Its preparation phase can outlast startup of the other services.

The controller is still under active development; verify each service's reported status rather than treating a process-start message as proof that the service is ready. In particular, Alice's Luvit process is launched without redirecting its standard output/error because redirected streams have caused problems in this environment. If the controller reports that Alice exits, try the direct launch below to separate a Luvit startup problem from a controller-launch problem.

### Option B: Launch Alice directly

To test the web server independently, run this from the project root:

```powershell
& (Get-Command luvit).Source .\web_server.lua
```

The expected startup messages include:

```text
[INFO] Alice server running on http://127.0.0.1:8080
[INFO] Local authentication layer enabled
```

Keep the process running and open [http://127.0.0.1:8080/](http://127.0.0.1:8080/) in your browser.

This direct command starts only Alice's web server. The memory service and llama.cpp must also be running for chat and memory features to work. Local evidence additionally requires the Rust Data Engine to be running and its corpus preparation to be complete.

### Manual service startup

When troubleshooting, run each process in its own terminal so its output remains visible.

Start memory:

```powershell
.\.venv\Scripts\python.exe .\memory_service.py
```

Start inference:

```powershell
.\bin\llama-server.exe -m .\model\YOUR_MODEL.gguf -c 8192 --host 127.0.0.1 --port 50006
```

Replace `YOUR_MODEL.gguf` with the actual filename. If `llama-server.exe` is on `PATH` instead, invoke that executable.

Start Alice from the repository root:

```powershell
luvit .\web_server.lua
```

The Rust Data Engine has its own command-line arguments and corpus preparation process; follow the companion repository's README for the selected dataset format.

## Alice's tools and evidence

The available tool set includes:

- `current_time` — retrieve the current time.
- `dice_roll` — roll dice, optionally returning individual rolls.
- `memory_store` and `memory_search` — persist and search semantic memories.
- `web_search` — search the web through the configured provider boundary.
- `EvidenceCorpus` — discover the active local corpus identifier.
- `EvidenceHunt` — search for records relevant to a term or query.
- `EvidenceGather` — retrieve bounded evidence from selected records.

The local evidence workflow separates finding a relevant record from retrieving its content. Evidence returned to the model is bounded, and the Rust engine owns corpus indexing and extraction. The active corpus identifier is discovered through the API instead of being assumed by the model.

Alice keeps tool execution in the Lua runtime. A model's tool-call request is not itself evidence that the tool succeeded; Alice executes the tool and supplies its result to the model. Tool failures should remain distinguishable from successful empty results.

## Conversation history and semantic memory

Conversation history is stored separately in `conversation_history.json`. ChromaDB-backed semantic memory is persisted beneath the memory directory (currently `memory/chroma`).

- Conversation history preserves the conversational exchange.
- Semantic memory stores selected information for later retrieval.
- The memory service exposes local HTTP endpoints; Lua tools access it through `memory_client.lua`.

These stores serve different purposes and should not be treated as interchangeable.

## Request boundaries and provenance

Each incoming human message starts a new request. Conversation history supplies context; it is not authorization to resume old tool work.

- Tool execution belongs to the current request.
- A failed or tool-limited request is terminal once Alice reports the failure.
- A retry or continuation must be established by the current message.
- Request IDs and terminal request state help separate current execution from stale asynchronous work.
- The Lua response layer can add a concise **Tools executed** section, distinguishing successful and failed calls.

Observability records request boundaries, model-round decisions, tool calls, and terminal outcomes. These are execution records, not model reasoning or chain-of-thought.

The design goal is traceable provenance across discovery, retrieval, tool execution, and presentation.

## Web search behavior

The current provider pool is DuckDuckGo HTML with Mojeek HTML fallback.

- An access challenge, HTTP failure, timeout, or unusable response is a provider failure—not a successful search with zero results.
- A successful search with no matching results is a valid empty result.
- Search attempts are bounded per request, and duplicate normalized queries are rejected.
- The model should not interpret provider failure as evidence that a subject does not exist.

Provider diagnostics are intended for operator troubleshooting and are bounded rather than dumping arbitrary response bodies into normal chat.

## Tests

The repository includes regression tests for request boundaries, response policy, and web-search behavior:

```text
tests/request_boundary.lua
tests/response_policy.lua
tests/web_search.lua
```

Run them with the test commands documented by the individual test files or the current development workflow. The Windows controller and the full multi-service startup still need to be validated in the target Windows environment; a passing unit test is not a substitute for an end-to-end startup test.

## Troubleshooting

**Alice exits when launched by the controller**

Run `luvit .\web_server.lua` directly from the repository root. If that works, compare the controller's executable, arguments, and working directory with the direct invocation. Check whether the service actually responds on port 8080 before concluding that it is ready.

**Port already in use**

Stop the existing service or change the matching port configuration. The controller intentionally refuses to start when a configured port is already accepting connections, to avoid mistaking an unrelated process for Alice's service.

**Memory service does not start**

Run the selected Python interpreter with `-c "import chromadb"` and inspect the memory process output. Ensure the project's `.venv` contains ChromaDB.

**Inference does not become ready**

Check that `llama-server.exe` exists, the selected GGUF model is valid, and the server output reports successful model loading. Confirm that host and port match Alice's configuration.

**Evidence API is not listening**

Large corpus preparation can take a while and the API may not bind until preparation finishes. Inspect the evidence log for parsing or preparation errors. The controller reports evidence readiness separately from the core runtime.

## License

AliceWebAI is licensed under the GNU General Public License v3.0 or later. See `LICENSE.txt` for the license text.

## Author

Override Development
