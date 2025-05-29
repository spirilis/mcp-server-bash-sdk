#!/bin/bash
# Movie business logic implementation

# Source the core MCP server implementation
source "$(dirname "${BASH_SOURCE[0]}")/mcpserver_core.sh"

# Get movies currently playing
tool_get_movies() {
    local movies=$(cat << 'EOF' | jq -c '.'
[
    {"id": 1, "title": "Avengers: Endgame", "showTimes": ["10:00", "13:30", "17:00", "20:30"], "price": 12.99},
    {"id": 2, "title": "The Matrix Resurrections", "showTimes": ["11:00", "14:00", "18:30", "21:00"], "price": 11.99},
    {"id": 3, "title": "Dune", "showTimes": ["10:30", "13:00", "16:30", "20:00"], "price": 12.99},
    {"id": 4, "title": "No Time to Die", "showTimes": ["11:30", "15:00", "18:00", "21:30"], "price": 13.99}
]
EOF
    )
    
    echo "$movies"
    return 0
}

# Book movie tickets
tool_book_ticket() {
    local args="$1"
    
    local movie_id=$(echo "$args" | jq -r '.movieId')
    local show_time=$(echo "$args" | jq -r '.showTime')
    local num_tickets=$(echo "$args" | jq -r '.numTickets')
    
    if [[ -z "$movie_id" || ! "$movie_id" =~ ^[0-9]+$ || -z "$show_time" || -z "$num_tickets" || ! "$num_tickets" =~ ^[0-9]+$ ]]; then
        echo "null"
        return 1
    fi
    
    # Generate booking confirmation
    local total_price=$(echo "$num_tickets * 12.99" | bc)
    echo "{\"bookingId\": \"BK$(date +%s)\", \"movieId\": $movie_id, \"showTime\": \"$show_time\", \"numTickets\": $num_tickets, \"totalPrice\": $total_price}"
    return 0
}

# Start the MCP server
run_mcp_server "$@"