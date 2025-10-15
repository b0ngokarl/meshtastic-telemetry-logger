#!/bin/bash

# Traceroute Collection Module for Meshtastic Telemetry Logger
# This module handles traceroute collection and routing topology analysis

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

# Global list of monitored addresses (filled lazily so standalone invocations work)
declare -a ADDRESSES

# File paths
ROUTING_LOG="${ROUTING_LOG:-routing_log.csv}"
RELATIONSHIPS_LOG="${RELATIONSHIPS_LOG:-node_relationships.csv}"

# Initialize routing log files
init_routing_logs() {
    if [ ! -f "$ROUTING_LOG" ]; then
        echo "timestamp,source,destination,direction,route_hops,signal_strengths,hop_count,success,error_reason" > "$ROUTING_LOG"
        debug_log "Created routing log: $ROUTING_LOG"
    fi
    
    if [ ! -f "$RELATIONSHIPS_LOG" ]; then
        echo "timestamp,node_a,node_b,signal_strength,relationship_type,last_heard" > "$RELATIONSHIPS_LOG"
        debug_log "Created relationships log: $RELATIONSHIPS_LOG"
    fi
}

# Parse traceroute output and extract routing information
parse_traceroute_output() {
    local output="$1"
    local destination="$2"
    local timestamp="$3"
    
    local forward_route=""
    local return_route=""
    local forward_signals=""
    local return_signals=""
    local forward_hops=0
    local return_hops=0
    
    # Parse forward route (towards destination)
    if echo "$output" | grep -q "Route traced towards destination:"; then
        local forward_line
        forward_line=$(echo "$output" | grep -A1 "Route traced towards destination:" | tail -1)
        
        # Example: !25048234 --> !ba4bf9d0 (6.0dB) --> !bff18ce4 (-3.5dB)
        debug_log "Forward route line: $forward_line"
        
        # Count hops by counting "-->" 
        forward_hops=$(echo "$forward_line" | grep -o -- "-->" | wc -l)
        
        # Extract clean route path (remove signal strengths first)
        forward_route=$(echo "$forward_line" | sed 's/ ([^)]*dB)//g' | sed 's/ --> /→/g')
        
        # Extract signal strengths in order (including negative values)
        forward_signals=$(echo "$forward_line" | grep -o '([^)]*dB)' | sed 's/[()]//g' | paste -sd ',' -)
        
        debug_log "Parsed forward: route='$forward_route', signals='$forward_signals', hops=$forward_hops"
    fi
    
    # Parse return route (back to us)
    if echo "$output" | grep -q "Route traced back to us:"; then
        local return_line
        return_line=$(echo "$output" | grep -A1 "Route traced back to us:" | tail -1)
        
        # Example: !bff18ce4 --> !ba4bf9d0 (-2.75dB) --> !25048234 (5.25dB)
        debug_log "Return route line: $return_line"
        
        # Count hops
        return_hops=$(echo "$return_line" | grep -o -- "-->" | wc -l)
        
        # Extract clean route path (remove signal strengths first)
        return_route=$(echo "$return_line" | sed 's/ ([^)]*dB)//g' | sed 's/ --> /→/g')
        
        # Extract signal strengths in order (including negative values)
        return_signals=$(echo "$return_line" | grep -o '([^)]*dB)' | sed 's/[()]//g' | paste -sd ',' -)
        
        debug_log "Parsed return: route='$return_route', signals='$return_signals', hops=$return_hops"
    fi
    
    # Determine source node (first node in forward route or auto-detect from our radio)
    local source_node
    if [ -n "$forward_route" ]; then
        # Extract first node from the route (before first →)
        source_node=$(echo "$forward_route" | sed 's/→.*//')
    else
        # Try to get our node ID from meshtastic CLI
        source_node=$(exec_meshtastic_command 10 --info 2>/dev/null | grep "My node info:" | awk '{print $4}' || echo "!local")
    fi
    
    # Log routing data
    if [ -n "$forward_route" ]; then
        echo "$timestamp,$source_node,$destination,forward,\"$forward_route\",\"$forward_signals\",$forward_hops,true," >> "$ROUTING_LOG"
        debug_log "Logged forward route: $source_node → $destination ($forward_hops hops)"
    fi
    
    if [ -n "$return_route" ]; then
        echo "$timestamp,$destination,$source_node,return,\"$return_route\",\"$return_signals\",$return_hops,true," >> "$ROUTING_LOG"
        debug_log "Logged return route: $destination → $source_node ($return_hops hops)"
    fi
    
    # Log node relationships for topology mapping
    log_node_relationships "$forward_route" "$forward_signals" "$timestamp"
    log_node_relationships "$return_route" "$return_signals" "$timestamp"
}

# Log individual node relationships from a route
log_node_relationships() {
    local route="$1"
    local signals="$2" 
    local timestamp="$3"
    
    if [ -z "$route" ]; then
        return
    fi
    
    # Split route into nodes
    IFS='→' read -ra nodes <<< "$route"
    IFS=',' read -ra signal_array <<< "$signals"
    
    # Log each hop relationship
    local i=0
    while [ $i -lt $((${#nodes[@]} - 1)) ]; do
        local node_a="${nodes[$i]}"
        local node_b="${nodes[$((i + 1))]}"
        local signal="${signal_array[$i]:-unknown}"
        
        # Clean up node IDs
        node_a=$(echo "$node_a" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        node_b=$(echo "$node_b" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        
        if [ -n "$node_a" ] && [ -n "$node_b" ]; then
            echo "$timestamp,$node_a,$node_b,$signal,direct_route,$timestamp" >> "$RELATIONSHIPS_LOG"
            debug_log "Logged relationship: $node_a ↔ $node_b ($signal)"
        fi
        
        i=$((i + 1))
    done
}

# Run traceroute for a single destination
run_traceroute() {
    local destination="$1"
    local timestamp
    timestamp=$(iso8601_date)
    
    # Strip quotes from destination to prevent issues with the CLI
    local clean_destination
    clean_destination=$(echo "$destination" | sed "s/^'//; s/'$//; s/^\"//; s/\"$//")
    
    debug_log "Running traceroute to $clean_destination (original: $destination)"
    
    # Run the traceroute command with timeout using the raw command executor
    local output
    local traceroute_timeout
    traceroute_timeout=${TRACEROUTE_TIMEOUT:-$TELEMETRY_TIMEOUT}
    output=$(exec_meshtastic_raw_command "$traceroute_timeout" --traceroute "$clean_destination")
    local exit_code=$?
    
    debug_log "Traceroute command output: $output"
    debug_log "Traceroute exit code: $exit_code"
    
    # Check for successful traceroute based on content, not just exit code
    # (meshtastic may return non-zero exit code due to protocol errors but still provide route data)
    if echo "$output" | grep -q "Route traced"; then
        debug_log "Traceroute to $clean_destination successful (found route data)"
        parse_traceroute_output "$output" "$clean_destination" "$timestamp"
        return 0
    else
        # Log failed traceroute
        local error_reason="timeout_or_unreachable"
        if echo "$output" | grep -q "Timed out"; then
            error_reason="timeout"
        elif echo "$output" | grep -q "ERROR"; then
            error_reason="error"
        fi
        
        # Get source node from config or auto-detect
        local source_node="!local"  # Will be improved to auto-detect
        echo "$timestamp,$source_node,$clean_destination,forward,,,0,false,$error_reason" >> "$ROUTING_LOG"
        debug_log "Traceroute to $clean_destination failed: $error_reason"
        return 1
    fi
}

# Run traceroutes for all monitored nodes
run_traceroutes_sequential() {
    echo "🗺️  Running network traceroutes..."
    if type load_config >/dev/null 2>&1; then
        load_config
    fi

    ensure_addresses_array
    refresh_node_cache_for_traceroute
    init_routing_logs
    
    local successful=0
    local failed=0
    
    for addr in "${ADDRESSES[@]}"; do
        echo "  📍 Tracing route to $addr..."
        
        if run_traceroute "$addr"; then
            successful=$((successful + 1))
            echo "    ✅ Traceroute completed"
        else
            failed=$((failed + 1))
            echo "    ❌ Traceroute failed"
        fi
        
        # Small delay between traceroutes to avoid overwhelming the network
        sleep 2
    done
    
    echo "🗺️  Traceroute collection completed: $successful successful, $failed failed"
    summarize_traceroute_recency
}

# Analyze routing changes by comparing with previous data
analyze_routing_changes() {
    debug_log "Analyzing routing changes..."
    
    if [ ! -f "$ROUTING_LOG" ]; then
        debug_log "No routing log found for change analysis"
        return
    fi
    
    # This function will be expanded to detect:
    # - Route changes (different hops)
    # - New direct connections
    # - Lost connections
    # - Signal strength changes
    
    local current_time
    current_time=$(iso8601_date)
    
    # For now, just log that analysis was attempted
    debug_log "Routing change analysis completed at $current_time"
}

# Ensure the addresses array is populated from MONITORED_NODES when not already set
ensure_addresses_array() {
    if [ ${#ADDRESSES[@]} -gt 0 ]; then
        return
    fi

    local raw="${MONITORED_NODES:-}"
    if [ -z "$raw" ]; then
        debug_log "No monitored nodes defined for traceroutes"
        ADDRESSES=()
        return
    fi

    IFS=',' read -ra __temp_addresses <<< "$raw"
    ADDRESSES=()
    for entry in "${__temp_addresses[@]}"; do
        entry=$(echo "$entry" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//')
        if [ -n "$entry" ]; then
            ADDRESSES+=("$entry")
        fi
    done
}

# Refresh the node cache so downstream modules pick up latest metadata
refresh_node_cache_for_traceroute() {
    if ! type load_config >/dev/null 2>&1; then
        debug_log "load_config not available; skipping node cache refresh"
        return
    fi

    load_config

    # Source telemetry helpers if the parser functions are missing
    if ! declare -f update_nodes_log >/dev/null 2>&1 || ! declare -f parse_nodes_to_csv >/dev/null 2>&1; then
        if [ -f "$SCRIPT_DIR/telemetry_collector.sh" ]; then
            # shellcheck disable=SC1090
            source "$SCRIPT_DIR/telemetry_collector.sh"
        fi
    fi

    if ! declare -f update_nodes_log >/dev/null 2>&1 || ! declare -f parse_nodes_to_csv >/dev/null 2>&1; then
        debug_log "Telemetry node parsers unavailable; cannot refresh node cache"
        return
    fi

    debug_log "Refreshing node cache prior to traceroutes"

    if update_nodes_log; then
        if parse_nodes_to_csv "$NODES_LOG" "$NODES_CSV"; then
            debug_log "Node cache CSV updated: $NODES_CSV"
            if declare -f load_node_info_cache >/dev/null 2>&1; then
                load_node_info_cache
            fi
        else
            debug_log "Failed to parse nodes log into CSV"
        fi
    else
        debug_log "Failed to update nodes log from Meshtastic CLI"
    fi
}

# Produce a quick summary of recent traceroute successes and failures
summarize_traceroute_recency() {
    if ! command -v python3 >/dev/null 2>&1; then
        debug_log "python3 unavailable; skipping traceroute recency summary"
        return
    fi

    if [ ! -f "$ROUTING_LOG" ]; then
        debug_log "Routing log not found; cannot summarize traceroutes"
        return
    fi

    echo ""
    echo "Recent traceroute results:"
    python3 <<'PY'
import csv
import os
from datetime import datetime, timezone
from pathlib import Path

path = Path(os.environ.get("ROUTING_LOG", "routing_log.csv"))
if not path.exists():
    raise SystemExit

records = {}

def update_record(dest, key, timestamp, extra=None):
    if not timestamp:
        return
    try:
        dt = datetime.fromisoformat(timestamp)
    except ValueError:
        return
    store = records.setdefault(dest, {})
    current = store.get(key)
    if current is None or dt > current[0]:
        store[key] = (dt, extra)

with path.open(newline="") as fh:
    reader = csv.DictReader(fh)
    for row in reader:
        dest = row.get("destination", "")
        ts = row.get("timestamp", "")
        direction = row.get("direction", "forward")
        success = row.get("success", "").lower() == "true"
        if not dest or direction != "forward":
            continue
        if success:
            update_record(dest, "success", ts, row.get("hop_count", ""))
        else:
            reason = row.get("error_reason", "") or "unknown"
            update_record(dest, "failure", ts, reason)

def fmt(dt):
    if dt is None:
        return "-", "-"
    stamp = dt[0].isoformat()
    now = datetime.now(dt[0].tzinfo or timezone.utc)
    delta = now - dt[0].astimezone(now.tzinfo)
    hours = delta.total_seconds() / 3600
    ago = f"{hours:.1f}h" if hours < 72 else f"{hours/24:.1f}d"
    return stamp, ago

def note_text(success_info, failure_info):
    if failure_info and failure_info[1] not in (None, ""):
        return failure_info[1]
    if success_info and success_info[1] not in (None, ""):
        return f"hops={success_info[1]}"
    return "-"

header = f"{'Destination':<14} {'Last success':<25} {'Age':<8} {'Last failure':<25} {'Age':<8} {'Note':<12}"
print(header)
print("-" * len(header))

for dest in sorted(records):
    success_info = fmt(records[dest].get('success'))
    failure_info = fmt(records[dest].get('failure'))
    note = note_text(records[dest].get('success'), records[dest].get('failure'))
    print(f"{dest:<14} {success_info[0]:<25} {success_info[1]:<8} {failure_info[0]:<25} {failure_info[1]:<8} {note:<12}")
PY
}