#!/bin/bash
# mcpserver_core.sh - Core MCP (Model Context Protocol) server implementation
# Handles JSON-RPC 2.0 messaging and MCP protocol infrastructure

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Log file path
LOG_FILE="$SCRIPT_DIR/mcpserver.log"

# Function to log messages to file
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Create logs directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Append log message to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to read a JSON file and convert it to a single line
read_json_file() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        # Read the file and remove all newlines and unnecessary whitespace
        jq -c '.' "$file_path"
    else
        echo "{\"error\": \"File not found: $file_path\"}" | jq -c '.'
    fi
}

# ==== MCP Protocol Core Implementation ====

# Function to handle MCP initialize method
handle_initialize() {
    local id="$1"
    local params="$2"
    
    # Parse client info and capabilities from params
    local client_info=$(echo "$params" | jq '.clientInfo')
    local client_capabilities=$(echo "$params" | jq '.capabilities')
    local client_protocol_version=$(echo "$params" | jq -r '.protocolVersion')
    
    # Use the configuration from mcpserverconfig.json file
    local config_file="$SCRIPT_DIR/assets/mcpserverconfig.json"
    local result=$(read_json_file "$config_file")
    
    create_response "$id" "$result" ""
}

# Function to list available tools
handle_tools_list() {
    local id="$1"
    
    # Read tools list from JSON file
    local tools_file="$SCRIPT_DIR/assets/tools_list.json"
    local result=$(read_json_file "$tools_file")
    create_response "$id" "$result" ""
}

# Function to handle tool calls - delegates to tool implementations
handle_tools_call() {
    local id="$1"
    local params="$2"
    
    local tool_name=$(echo "$params" | jq -r '.name')
    local arguments=$(echo "$params" | jq '.arguments // {}')
    local result error content
    
    # Log the tool being called
    log "INFO" "Tool call: $tool_name with arguments: $(echo "$arguments" | jq -c '.')"
    
    # Call the function from the main script if it exists
    if type "tool_${tool_name}" &>/dev/null; then
        # Call the specific tool function from main script
        content=$(tool_${tool_name} "$arguments")
        
        # Check if we got an error
        if [[ $? -ne 0 || "$content" == "null" ]]; then
            local error_file="$SCRIPT_DIR/assets/invalid_tool_error.json"
            if [[ -f "$error_file" ]]; then
                error=$(read_json_file "$error_file")
                create_response "$id" "$error" ""
                return
            else
                error=$(create_error -32603 "Tool execution error for $tool_name")
                create_response "$id" "null" "$error"
                return
            fi
        fi
    else
        # Read error template for unknown tool
 
        error=$(create_error -32601 "Tool not found: $tool_name")
 
        create_response "$id" "null" "$error"
        return
    fi
    
    # We need to ensure proper JSON encoding for the content by using jq
    # First, stringify the content (convert it to a JSON string)
    local stringified_content=$(echo "$content" | jq -c 'tostring')
    
    # Then build the response structure with the stringified content
    result="{
        \"content\": [{
            \"type\": \"text\",
            \"text\": $stringified_content
        }]
    }"
    
    create_response "$id" "$result" ""
}

# ==== JSON-RPC 2.0 Handler ====

# Function to create a JSON-RPC 2.0 response
create_response() {
    local id="$1"
    local result="$2"
    local error="$3"
    local response
    
    if [[ -n "$error" ]]; then
        response="{\"jsonrpc\": \"2.0\", \"error\": $error, \"id\": $id}"
    else
        response="{\"jsonrpc\": \"2.0\", \"result\": $result, \"id\": $id}"
    fi
    
    # Ensure the response is properly formatted as a single line JSON with no newlines
    local formatted_response=$(echo "$response" | jq -c '.')
    
    # Log the response
    log "RESPONSE" "$formatted_response"
    
    # Output the response
    echo "$formatted_response"
}

# Function to create a JSON-RPC 2.0 error
create_error() {
    local code="$1"
    local message="$2"
    
    echo "{\"code\": $code, \"message\": \"$message\"}"
}

# Function to process a JSON-RPC 2.0 request
process_request() {
    local input="$1"
    local jsonrpc version id method params result error
    
    # Parse the JSON-RPC 2.0 request
    jsonrpc=$(echo "$input" | jq -r '.jsonrpc')
    # Extract the ID exactly as received, preserving its format (string, number, null)
    id=$(echo "$input" | jq -c '.id')
    method=$(echo "$input" | jq -r '.method')
    params=$(echo "$input" | jq '.params')
    
    # Log the method being called
    log "INFO" "Processing method: $method (id: $id)"
    
    # Validate JSON-RPC 2.0 version
    if [[ "$jsonrpc" != "2.0" ]]; then
        error=$(create_error -32600 "Invalid Request: Not a JSON-RPC 2.0 request")
        create_response "$id" "null" "$error"
        return
    fi
    
    # Process the method
    case "$method" in
        # MCP Protocol Methods
        "initialize")
            handle_initialize "$id" "$params"
            ;;
        "tools/list")
            handle_tools_list "$id"
            ;;
        "tools/call")
            handle_tools_call "$id" "$params"
            ;;
        "notifications/initialized")
            # Don't invoke any response, just log it
            log "INFO" "Host confirmed toolContract reception with 'notifications/initialized'"
            return
            ;;
            
        *)
            error=$(create_error -32601 "Method not found: $method")
            create_response "$id" "null" "$error"
            ;;
    esac
}

# ==== Main execution ====
run_mcp_server() {
    # Check if we have jq installed
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is required but not installed. Install it using: brew install jq" >&2
        exit 1
    fi

    # Check if reading from a file or continuous stdin
    if [[ -n "$1" ]]; then
        # Read from file if provided as argument
        input=$(cat "$1")
        
        # Log the input
        log "REQUEST" "$input"
        
        # Process the JSON-RPC 2.0 request
        response=$(process_request "$input")
        
        # Output the response
        echo "$response" 
    else
        # Continuously read from stdin line by line
        
        log "INFO" "MCP Server started. Waiting for JSON-RPC 2.0 messages..."
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines or notifications/initialized messages
            if [[ -z "$line" || "$line" == *"\"method\":\"notifications/initialized\""* ]]; then
                # Log notifications/initialized but don't process it
                if [[ "$line" == *"\"method\":\"notifications/initialized\""* ]]; then
                    log "INFO" "Host confirmed toolContract reception with 'notifications/initialized'"
                fi
                continue
            fi
            
            # Log the input
            log "REQUEST" "$line"
            
            # Process the JSON-RPC 2.0 request
            response=$(process_request "$line")
            
            # Output the response
            echo "$response"
        done
    fi
}