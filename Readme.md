# AliceWebAI

AliceWebAI is a local web interface for Ollama-powered LLMs with a Lua/Luvit middleware layer providing behavioral overrides for common LLM behaviors.

# Why Alice Exists
Alice began on September 4, 2026, after an AI model repeatedly denied receiving a prompt until presented with a screenshot.

That frustrated me enough to take a look at what I'd picked up over more than a decade of IT Systems Engineering focused on integrating disparate systems and ask myself:

What happens if I put a tool between the human and the model? A tool designed to give humans better agency.

Thus, Alice was created.

And no, the name isn't a technology reference. It's a Lewis Carroll reference.


## Setup

1. Install Lua 5.1.

   * Windows: Use Lua for Windows.
   * Linux: Install Lua 5.1 through `apt-get`.

2. Install Luvit if it is not already present after the Lua installation.

   Verify:

   ```text
   luvit --version
   ```

3. Install the required Lua modules using LuaRocks.

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

4. Install Ollama.

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

5. Clone this repository.

6. Open one PowerShell terminal in the AliceWebAI directory.

7. Open a second PowerShell terminal and run:

   ```powershell
   ollama serve
   ```

8. Return to the terminal in the AliceWebAI directory and run:

   ```powershell
   luvit web_server.lua
   ```

9. Open your browser and go to:

   ```text
   http://127.0.0.1:8080
   ```

10. Chat and interact with Alice with the added benefit of behavioral overrides available to **you**.

## License

AliceWebAI is licensed under the GNU General Public License v3.0.

See `LICENSE` for the complete license text.

## Author

Override Development
