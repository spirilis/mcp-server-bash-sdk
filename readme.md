# 🐚 Building an MCP Server in Shell (Yes, Bash)

> Lightweight. Portable. Zero-overhead. Good enough.

---

## 💭 The Problem

I wanted to build an **MCP server** — a component that talks JSON-RPC over stdio, following the [Model Context Protocol (MCP)](https://modelcontextprotocol.io). But I didn't want the overhead of Node.js, Python, or any heavy runtime.

Most MCP servers are just API wrappers with schema conversion. So why add runtime overhead when a lightweight shell script could do the job?

---

## 📡 What's Actually Happening Under the Hood?

### JSON-RPC: Simple Remote Procedure Calls

JSON-RPC is just a lightweight protocol for remote procedure calls using JSON. It has minimal structure:

```json
// Request
{
  "jsonrpc": "2.0",  // Version
  "method": "get_movies",  // Function to call
  "params": {},  // Arguments
  "id": 1  // Request identifier
}

// Response
{
  "jsonrpc": "2.0",
  "result": { "movies": [...] },  // Result data
  "id": 1  // Same ID as request
}
```

**Why use JSON-RPC?** It's minimal, language-agnostic, and works over any transport (HTTP, WebSocket, or in our case, stdio).  (also blockchain uses it, its after rpc era and before grpc era )

### stdio vs Traditional CLI

Traditional CLI tools are one-shot: they parse arguments, execute, and exit:

```bash
$ tool-name --get-movies
[movie data]
```

But with **stdio-based communication**, the process stays alive, reading from stdin and writing to stdout in a continuous loop:

```
[client] → stdin → [our MCP server] → stdout → [client]
```

This approach enables:
- **Stateful conversations**: The server process stays alive between requests
- **Structured communication**: Full JSON objects, not just command arguments
- **Bidirectional dialogue**: Continuous reading/writing vs one-shot execution
- **Perfect for MCP**: AI tools need to dynamically invoke different functions

---

## 🧩 How It Works: The Shell-Based MCP Stack

### 1. JSON Parsing with `jq`

Shell isn't great at JSON, but `jq` is. We use it for:

```bash
# Extract method name from request
method=$(echo "$input" | jq -r '.method')

# Create response
echo "{\"result\": $result}" | jq -c '.'
```

### 2. stdio Loop

The core of our MCP server is just a stdin reader:

```bash
# Continuously read from stdin line by line
while IFS= read -r line; do
  # Process the JSON-RPC request
  response=$(process_request "$line")
  
  # Write response to stdout
  echo "$response"
done
```

### 3. Function Dispatch System

We map RPC methods to Bash functions dynamically:

```bash
# Dynamic dispatch to tool_* functions
if type "tool_${tool_name}" &>/dev/null; then
  content=$(tool_${tool_name} "$arguments")
else
  # Error: tool not found
fi
```

### 4. Modular Design

- **mcpserver_core.sh**: JSON-RPC + MCP protocol handling
- **moviemcpserver.sh**: Just business logic functions
- **Configuration**: External JSON files for tools and server config

---

## 🔧 Why Shell Makes Sense Here

1. **Zero Runtime Overhead**
   - No interpreter startup (Python)
   - No VM warmup (Node.js, JVM)
   - No dependency resolution

2. **Perfect for Local Tool Execution**
   - Most MCP servers nowadays just call APIs anyway
   - The bottleneck is network calls, not local processing
   - Low-latency startup time is crucial

3. **Simplicity & Transparency**
   - Self-contained (~200 lines)
   - Easy to inspect and debug
   - No "magic" frameworks

4. **No external server**
   - It talks stdio directly to MCP hosts like Github Copilot agent (I have tested only there)

---

## 📦 What This MCP Server Handles

* ✅ Full JSON-RPC 2.0 protocol
* ✅ MCP required methods:
  - `initialize`: Server setup and capability exchange
  - `tools/list`: Advertises available tools
  - `tools/call`: Executes tool with arguments
  - `notifications/initialized`: Confirmation handling
* ✅ Dynamic tool loading via Bash functions
* ✅ Error handling and logging
* ✅ Configuration via JSON files

---

## 🚫 Limitations

* ❌ No concurrency/parallel processing
* ❌ Limited memory management
* ❌ No streaming responses
* ❌ Not designed for high throughput

But for AI assistants and local tool execution, these aren't blockers.

---

## 🛠 The Architecture

```
┌─────────────┐         ┌────────────────────────┐
│ MCP Host    │         │ MCP Server             │
│ (AI System) │◄──────► │ (moviemcpserver.sh)    │
└─────────────┘ stdio   └────────────────────────┘
                             │
                     ┌───────┴──────────┐
                     ▼                  ▼
              ┌─────────────────┐  ┌───────────────┐
              │ Protocol Layer  │  │ Business Logic│
              │(mcpserver_core.sh)│  │(tool_* funcs)│
              └─────────────────┘  └───────────────┘
                     │                  │
                     ▼                  ▼
              ┌─────────────────┐  ┌───────────────┐
              │ Configuration   │  │ External      │
              │ (JSON Files)    │  │ Services/APIs │
              └─────────────────┘  └───────────────┘
```

---

## 🔌 How to Extend This

Extending this MCP server is remarkably simple:

1. **Add a new tool function** in your business logic file (e.g., `moviemcpserver.sh`):

   ```bash
   # Add a function with the tool_ prefix
   tool_get_recommendations() {
     local args="$1"
     local genre=$(echo "$args" | jq -r '.genre')
     
     # Your implementation here
     echo "[{\"title\": \"Inception\", \"genre\": \"$genre\"}]"
     return 0
   }
   ```

2. **Update your `tools_list.json`** in the assets directory:

   ```json
   {
     "tools": [
       {
         "name": "get_recommendations",
         "description": "Get movie recommendations by genre",
         "parameters": {
           "type": "object",
           "properties": {
             "genre": {
               "type": "string",
               "description": "Movie genre (e.g., action, comedy)"
             }
           },
           "required": ["genre"]
         }
       },
       // ...existing tools...
     ]
   }
   ```

3. **That's it!** No need to modify the core MCP protocol handling.

The modular design means:
- The core protocol layer (`mcpserver_core.sh`) handles all the JSON-RPC mechanics
- Your business logic file (`moviemcpserver.sh`) stays clean and focused
- New tools are auto-discovered by the function naming convention (`tool_*`)

This makes it perfect for quickly prototyping new AI tools without framework overhead.

## 🧠 Final Thought

LLM tool building doesn't always need complex frameworks. Sometimes a 200-line shell script solves 90% of the problem.

This project is my bet on simplicity — shell scripting still has its place in the AI era.

