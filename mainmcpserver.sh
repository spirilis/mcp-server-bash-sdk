#!/bin/bash
# productserver.sh - MCP (Model Context Protocol) server implementation with JSON-RPC 2.0
# This script reads JSON-RPC 2.0 messages, parses them, and handles MCP protocol methods

# Make the script executable if needed: chmod +x productserver.sh

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Log file path
LOG_FILE="$SCRIPT_DIR/logs/log.txt"

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

# Dependencies: jq (JSON parser)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Install it using: brew install jq" >&2
    exit 1
fi

# MCP Protocol Server Constants - Now loaded from mcpserverconfig.json
# Values are now retrieved from the config file at runtime

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

# ==== Define functions that can be called via RPC ====

# Function to get movies that are currently playing
get_movies() {
    # Static movie data
    local movies=$(cat << 'EOF' | jq -c '.'
[
    {"id": 1, "title": "Avengers: Endgame", "showTimes": ["10:00", "13:30", "17:00", "20:30"], "price": 12.99},
    {"id": 2, "title": "The Matrix Resurrections", "showTimes": ["11:00", "14:00", "18:30", "21:00"], "price": 11.99},
    {"id": 3, "title": "Dune", "showTimes": ["10:30", "13:00", "16:30", "20:00"], "price": 12.99},
    {"id": 4, "title": "No Time to Die", "showTimes": ["11:30", "15:00", "18:00", "21:30"], "price": 13.99}
]
EOF
    )
    
    # Return the movies data as a single line JSON string
    echo "$movies"
}

# Function to book a movie ticket
book_ticket() {
    local movie_id="$1"
    local show_time="$2"
    local num_tickets="$3"
    
    if [[ -z "$movie_id" || ! "$movie_id" =~ ^[0-9]+$ || -z "$show_time" || -z "$num_tickets" || ! "$num_tickets" =~ ^[0-9]+$ ]]; then
        echo "null"
        return 1
    fi
    
    # In a real scenario, this would check availability and add to a booking system
    # For this example, we'll just return a booking confirmation
    local total_price=$(echo "$num_tickets * 12.99" | bc)
    echo "{\"bookingId\": \"BK$(date +%s)\", \"movieId\": $movie_id, \"showTime\": \"$show_time\", \"numTickets\": $num_tickets, \"totalPrice\": $total_price}"
}

# ==== MCP Protocol Implementation ====

# Function to handle MCP initialize method
handle_initialize() {
    local id="$1"
    local params="$2"
    
    # Parse client info and capabilities from params
    local client_info=$(echo "$params" | jq '.clientInfo')
    local client_capabilities=$(echo "$params" | jq '.capabilities')
    local client_protocol_version=$(echo "$params" | jq -r '.protocolVersion')
    
    # Use the configuration from mcpserverconfig.json file
    local config_file="$SCRIPT_DIR/mcpserverconfig.json"
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

# Function to handle tool calls
handle_tools_call() {
    local id="$1"
    local params="$2"
    
    local tool_name=$(echo "$params" | jq -r '.name')
    local arguments=$(echo "$params" | jq '.arguments // {}')
    local result error content
    
    # Log the tool being called
    log "INFO" "Tool call: $tool_name with arguments: $(echo "$arguments" | jq -c '.')"
    
    case "$tool_name" in
        "get_movies")
            content=$(get_movies)
            ;;
        "book_ticket")
            local movie_id=$(echo "$arguments" | jq -r '.movieId')
            local show_time=$(echo "$arguments" | jq -r '.showTime')
            local num_tickets=$(echo "$arguments" | jq -r '.numTickets')
            content=$(book_ticket "$movie_id" "$show_time" "$num_tickets")
            if [[ "$content" == "null" ]]; then
                local error_file="$SCRIPT_DIR/assets/invalid_booking_error.json"
                error=$(read_json_file "$error_file")
                create_response "$id" "$error" ""
                return
            fi
            ;;
        *)
            # Read error template and replace placeholder with actual tool name
            local error_file="$SCRIPT_DIR/assets/unknown_tool_error.json"
            error=$(read_json_file "$error_file" | sed "s/TOOL_NAME/$tool_name/")
            create_response "$id" "$error" ""
            return
            ;;
    esac
    
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
        # Use the ID exactly as received, without any modification
        response="{\"jsonrpc\": \"2.0\", \"error\": $error, \"id\": $id}"
    else
        # Use the ID exactly as received, without any modification
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
        *)
            error=$(create_error -32601 "Method not found: $method")
            create_response "$id" "null" "$error"
            ;;
    esac
}

# ==== Main execution ====

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

# Example usage:
# Echo a JSON-RPC 2.0 request and pipe it to the script
# echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "get_movies"}, "id": 1}' | ./productserver.sh
# echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "book_ticket", "arguments": {"movieId": 1, "showTime": "10:00", "numTickets": 2}}, "id": 2}' | ./productserver.sh
# Or save the request to a file and provide it as an argument
# ./productserver.sh request.json
# Or run in interactive mode where it waits for input
# ./productserver.sh