# AliceWebAI

AliceWebAI is a local web interface for Ollama-powered LLMs with a Lua/Luvit middleware layer providing behavioral overrides for common LLM behaviors and persistent semantic memory powered by ChromaDB.

# Why Alice Exists

Alice began on September 4, 2026, after an AI model repeatedly denied receiving a prompt until presented with a screenshot.

That frustrated me enough to take a look at what I'd picked up over more than a decade of IT Systems Engineering focused on integrating disparate systems and ask myself:

What happens if I put a tool between the human and the model? A tool designed to give humans better agency.

Thus, Alice was created.

And no, the name isn't a technology reference. It's a Lewis Carroll reference.

## Architecture

AliceWebAI currently consists of several cooperating local components:

```text
Browser
   |
   v
Luvit Web Server :8080
   |
   v
Alice / Lua Middleware
   |
   +--------------------+
   |                    |
   v                    v
Ollama :11434       Memory Tools
                        |
                        v
                 Python Memory Service :8090
                        |
                        v
                     ChromaDB
```

Ollama handles the LLM inference and tool selection.

The Lua/Luvit layer provides the web server, conversation handling, behavioral overrides, and tool orchestration.

The Python memory service provides an HTTP bridge between Lua and ChromaDB.

ChromaDB provides persistent semantic memory for Alice.

Conversation history remains stored separately in `conversation_history.json`.

## Setup

### 1. Install Lua 5.1

* Windows: Use Lua for Windows.
* Linux: Install Lua 5.1 through `apt-get`.

### 2. Install Luvit

Install Luvit if it is not already present after the Lua installation.

Verify:

```text
luvit --version
```

### 3. Install the required Lua modules

Using LuaRocks:

PowerShell:

```powershell
luarocks install luasocket
luarocks install dkjson
```

Linux:

```bash
luarocks install luasocket
luarocks install dkjson
```

### 4. Install Python

Alice's persistent semantic memory service requires Python.

Verify that Python is available:

PowerShell:

```powershell
python --version
```

Linux:

```bash
python3 --version
```

### 5. Clone this repository

Clone the AliceWebAI repository and change into the project directory.

### 6. Create the Python virtual environment

PowerShell:

```powershell
python -m venv .venv
```

Activate it:

```powershell
.venv\Scripts\Activate.ps1
```

Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 7. Install the Python memory dependencies

With the virtual environment activated:

```powershell
pip install chromadb
```

Linux:

```bash
pip install chromadb
```

ChromaDB stores Alice's persistent semantic memory beneath the project's memory directory.

The first use of semantic memory may download the embedding model used by ChromaDB. This can take some time on the first run.

### 8. Install Ollama

Windows PowerShell:

```powershell
irm https://ollama.com/install.ps1 | iex
```

Follow the installation prompts, then install the Gemma model:

```powershell
ollama pull gemma4:26b
```

Linux: Install Ollama using the installation instructions provided by Ollama, then install the model:

```bash
ollama pull gemma4:26b
```

### 9. Start Ollama

Open a PowerShell terminal in the AliceWebAI directory and start Ollama:

```powershell
ollama serve
```

Leave this terminal running.

### 10. Start the Alice memory service

Open another terminal in the AliceWebAI directory.

Activate the Python virtual environment:

```powershell
.venv\Scripts\Activate.ps1
```

Start the memory service:

```powershell
python memory_service.py
```

The service listens locally on:

```text
http://127.0.0.1:8090
```

Leave this terminal running.

The memory service provides the HTTP bridge between Alice's Lua memory tools and ChromaDB.

### 11. Start the Alice web server

Open another terminal in the AliceWebAI directory and run:

```powershell
luvit web_server.lua
```

The web server listens locally on:

```text
http://127.0.0.1:8080
```

### 12. Open Alice

Open your browser and go to:

```text
http://127.0.0.1:8080
```

Chat and interact with Alice with the added benefit of behavioral overrides available to **you**.

Alice can also use her persistent semantic memory tools to store and retrieve information from ChromaDB.

## Running Alice

When running the complete system locally, the following processes should remain active:

```text
Terminal 1
    ollama serve

Terminal 2
    python memory_service.py

Terminal 3
    luvit web_server.lua
```

The Python memory service and Luvit web server communicate locally over HTTP.

Ollama should remain bound to:

```text
127.0.0.1:11434
```

The Alice memory service should remain bound to:

```text
127.0.0.1:8090
```

The Luvit web server should remain bound to:

```text
127.0.0.1:8080
```

Using `127.0.0.1` explicitly avoids relying on local hostname resolution when connecting between the Lua middleware and Ollama.

## Semantic Memory

Alice's long-term semantic memory is provided by ChromaDB.

Two Lua tools currently provide access to the memory system:

* `memory_store` stores information in Alice's persistent semantic memory.
* `memory_search` performs semantic searches against stored memories.

The Lua tools communicate with the Python memory service through `memory_client.lua`.

The Python service manages the ChromaDB collection and persistent storage.

Memory is separate from Alice's normal conversation history. Conversation history is stored in:

```text
conversation_history.json
```

while semantic memories are persisted through ChromaDB beneath:

```text
memory/chroma
```

The first semantic-memory operation may take longer than subsequent operations because ChromaDB may need to initialize or download its embedding model.

## Behavioral Overrides

Alice includes a middleware layer capable of detecting and applying behavioral overrides for common LLM behaviors.

These overrides can be applied through Alice's existing command and web interfaces and are maintained separately from Alice's persistent semantic memory.

The purpose is to give the human interacting with the model greater visibility and control over how the model responds.

## License

AliceWebAI is licensed under the GNU General Public License v3.0.

See `LICENSE.txt` for the complete license text.

## Author

Override Development
