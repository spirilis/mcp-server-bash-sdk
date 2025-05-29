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

## 🔌 How to Create Your Own MCP Server

Creating your own MCP server with this framework is incredibly simple. You just need to focus on your business logic while `mcpserver_core.sh` handles all the complex protocol details.

### 1. Create Your Business Logic Script

Create a new file (e.g., `weatherserver.sh`) with your tool implementations:

```bash
#!/bin/bash
# Weather API MCP server implementation

# Source the core MCP server implementation
source "$(dirname "${BASH_SOURCE[0]}")/mcpserver_core.sh"

# Environment variables passed from MCP host
API_KEY="${MCP_API_KEY:-default_key}"  # Use MCP_API_KEY or default
UNITS="${MCP_UNITS:-metric}"           # Use MCP_UNITS or "metric"

# Get current weather for a location
tool_get_weather() {
  local args="$1"
  local location=$(echo "$args" | jq -r '.location')
  
  # Call external weather API
  local weather=$(curl -s "https://api.example.com/weather?location=$location&units=$UNITS&apikey=$API_KEY")
  
  # Return the result
  echo "$weather"
  return 0
}

# Get weather forecast for multiple days
tool_get_forecast() {
  local args="$1"
  local location=$(echo "$args" | jq -r '.location')
  local days=$(echo "$args" | jq -r '.days')
  
  # Call external forecast API
  local forecast=$(curl -s "https://api.example.com/forecast?location=$location&days=$days&units=$UNITS&apikey=$API_KEY")
  
  echo "$forecast"
  return 0
}

# Start the MCP server
run_mcp_server "$@"
```

Make it executable:
```bash
chmod +x weatherserver.sh
```

### 2. Create Your `tools_list.json`

In the `assets` directory, create or update `tools_list.json`:

```json
{
  "tools": [
    {
      "name": "get_weather",
      "description": "Get current weather for a location",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {
            "type": "string",
            "description": "City name or coordinates"
          }
        },
        "required": ["location"]
      }
    },
    {
      "name": "get_forecast",
      "description": "Get weather forecast for multiple days",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {
            "type": "string",
            "description": "City name or coordinates"
          },
          "days": {
            "type": "integer",
            "description": "Number of days to forecast"
          }
        },
        "required": ["location", "days"]
      }
    }
  ]
}
```

### 3. Update Your `mcpserverconfig.json`

Customize the server configuration:

```json
{
  "protocolVersion": "0.1.0",
  "serverInfo": {
    "name": "WeatherServer",
    "version": "1.0.0"
  },
  "capabilities": {
    "tools": {
      "listChanged": true
    }
  },
  "instructions": "This server provides weather information and forecasts. You can get current weather or multi-day forecasts for any location."
}
```

### 4. That's It! No Protocol Details To Worry About

The beauty of this design is that:
- `mcpserver_core.sh` handles all JSON-RPC and MCP protocol requirements
- Your script only needs to implement `tool_*` functions for your specific use case
- Environment variables from the MCP host can be accessed directly
- Tool discovery happens automatically by function naming convention

This modular approach lets you focus entirely on your tools' functionality rather than protocol implementation details.

## 🧠 Final Thought

LLM tool building doesn't always need complex frameworks. Sometimes a 200-line shell script solves 90% of the problem.

This project is my bet on simplicity — shell scripting still has its place in the AI era.

---

## 🔌 Using with VS Code & GitHub Copilot

Setting up your MCP server with GitHub Copilot is simple:

1. **Add to VS Code settings.json**:

```jsonc
"mcp": {
    "servers": {
        "my-movie-server": {
            "type": "stdio",
            "command": "/path/to/your/moviemcpserver.sh",
            "args": []
        }
    }
}
```

2. **Make it executable**:

```bash
chmod +x /path/to/your/moviemcpserver.sh
```

3. **Use with GitHub Copilot Chat**:

```
/mcp my-movie-server get movies
```

That's it! You're now using a lightweight MCP server with GitHub Copilot.

**The complete code is available at: https://github.com/muthuishere/mcp-server-bash-sdk**

