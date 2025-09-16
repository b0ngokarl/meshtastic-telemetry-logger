#!/bin/bash

# Traceroute Collection Module for Meshtastic Telemetry Logger
# This module handles traceroute collection and routing topology analysis

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

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
    
    debug_log "Running traceroute to $destination"
    
    # Run the traceroute command with timeout
    local output
    output=$(exec_meshtastic_command "$TELEMETRY_TIMEOUT" --traceroute "$destination" 2>&1)
    local exit_code=$?
    
    debug_log "Traceroute command output: $output"
    debug_log "Traceroute exit code: $exit_code"
    
    # Check for successful traceroute based on content, not just exit code
    # (meshtastic may return non-zero exit code due to protocol errors but still provide route data)
    if echo "$output" | grep -q "Route traced"; then
        debug_log "Traceroute to $destination successful (found route data)"
        parse_traceroute_output "$output" "$destination" "$timestamp"
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
        echo "$timestamp,$source_node,$destination,forward,,,0,false,$error_reason" >> "$ROUTING_LOG"
        debug_log "Traceroute to $destination failed: $error_reason"
        return 1
    fi
}

# Run traceroutes for all monitored nodes
run_traceroutes_sequential() {
    echo "🗺️  Running network traceroutes..."
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