#!/bin/bash

# Meshtastic Telemetry Logger Web Server Control Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSERVER_PY="$SCRIPT_DIR/webserver.py"
PID_FILE="$SCRIPT_DIR/webserver.pid"

show_usage() {
    cat << EOF
Meshtastic Telemetry Logger Web Server Control

Usage: $0 [command] [options]

Commands:
    start       Start the web server
    stop        Stop the web server
    restart     Restart the web server
    status      Show web server status
    logs        Show web server logs (if running in background)

Options:
    --port PORT         HTTP port (default: 8080)
    --ssl-port PORT     HTTPS port (default: 8443)
    --http-only         Run HTTP server only
    --https-only        Run HTTPS server only
    --background        Run in background (daemon mode)

Examples:
    $0 start                    # Start with default settings
    $0 start --port 8090        # Start HTTP on port 8090
    $0 start --https-only       # Start HTTPS only
    $0 start --background       # Start in background
    $0 status                   # Check if server is running
    $0 stop                     # Stop the server

Configuration is read from .env file if present.
EOF
}

start_webserver() {
    local args=()
    local background=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                args+=("--port" "$2")
                shift 2
                ;;
            --ssl-port)
                args+=("--ssl-port" "$2")
                shift 2
                ;;
            --http-only)
                args+=("--mode" "http")
                shift
                ;;
            --https-only)
                args+=("--mode" "https")
                shift
                ;;
            --background)
                background=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Check if already running
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "Web server is already running (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    # Start server
    if [ "$background" = true ]; then
        echo "Starting web server in background..."
        python3 "$WEBSERVER_PY" "${args[@]}" > webserver.log 2>&1 &
        local pid=$!
        echo $pid > "$PID_FILE"
        echo "Web server started with PID: $pid"
        echo "Logs: webserver.log"
        sleep 2
        if ! kill -0 $pid 2>/dev/null; then
            echo "Failed to start web server. Check webserver.log for errors."
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "Starting web server in foreground..."
        echo "Press Ctrl+C to stop"
        python3 "$WEBSERVER_PY" "${args[@]}"
    fi
}

stop_webserver() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Web server is not running (no PID file found)"
        return 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Web server is not running (process $pid not found)"
        rm -f "$PID_FILE"
        return 1
    fi
    
    echo "Stopping web server (PID: $pid)..."
    kill "$pid"
    
    # Wait up to 10 seconds for graceful shutdown
    local count=0
    while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "Forcing shutdown..."
        kill -9 "$pid"
    fi
    
    rm -f "$PID_FILE"
    echo "Web server stopped"
}

status_webserver() {
    if [ ! -f "$PID_FILE" ]; then
        echo "Web server is not running"
        return 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    
    if kill -0 "$pid" 2>/dev/null; then
        echo "Web server is running (PID: $pid)"
        
        # Try to check if ports are listening
        local listening_ports=""
        if command -v netstat >/dev/null 2>&1; then
            listening_ports=$(netstat -tlnp 2>/dev/null | grep ":808[0-9]" | grep "$pid" || true)
        elif command -v ss >/dev/null 2>&1; then
            listening_ports=$(ss -tlnp 2>/dev/null | grep ":808[0-9]" | grep "$pid" || true)
        fi
        
        if [ -n "$listening_ports" ]; then
            echo "Listening ports:"
            echo "$listening_ports"
        fi
        
        # Show log tail if available
        if [ -f "webserver.log" ]; then
            echo ""
            echo "Recent log entries:"
            tail -5 "webserver.log"
        fi
        
        return 0
    else
        echo "Web server is not running (process $pid not found)"
        rm -f "$PID_FILE"
        return 1
    fi
}

show_logs() {
    if [ -f "webserver.log" ]; then
        echo "Web server logs:"
        tail -f "webserver.log"
    else
        echo "No log file found (webserver.log)"
        return 1
    fi
}

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required but not found"
    echo "Please install Python 3 to use the web server"
    exit 1
fi

# Check if webserver.py exists
if [ ! -f "$WEBSERVER_PY" ]; then
    echo "Error: webserver.py not found at $WEBSERVER_PY"
    exit 1
fi

# Parse command
case "${1:-}" in
    start)
        shift
        start_webserver "$@"
        ;;
    stop)
        stop_webserver
        ;;
    restart)
        stop_webserver
        sleep 2
        shift
        start_webserver "$@"
        ;;
    status)
        status_webserver
        ;;
    logs)
        show_logs
        ;;
    help|--help|-h)
        show_usage
        ;;
    "")
        echo "No command specified"
        show_usage
        exit 1
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac