#!/bin/bash

# ML Power Predictor Testing and Simulation Script
# This script helps test the ML system by simulating prediction accuracy data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCURACY_LOG="$SCRIPT_DIR/prediction_accuracy.csv"
PREDICTIONS_LOG="$SCRIPT_DIR/power_predictions.csv"
TELEMETRY_LOG="$SCRIPT_DIR/telemetry_log.csv"

# Simulate some historical accuracy data for testing
simulate_accuracy_data() {
    echo "Simulating ML prediction accuracy data for testing..."
    
    # Get some real node IDs from predictions
    local nodes=($(tail -n +2 "$PREDICTIONS_LOG" 2>/dev/null | cut -d',' -f2 | sort -u))
    
    if [ ${#nodes[@]} -eq 0 ]; then
        echo "No prediction data found. Run ml_power_predictor.sh first."
        return 1
    fi
    
    # Generate some test accuracy data (6 hours ago)
    local test_time=$(date -u -d '6 hours ago' +%Y-%m-%dT%H:%M:%SZ)
    local pred_time=$(date -u -d '6 hours ago' +%Y-%m-%dT%H)
    
    for node in "${nodes[@]:0:3}"; do  # Test with first 3 nodes
        # Get current battery for this node
        local current_battery=$(grep ",$node,success" "$TELEMETRY_LOG" | tail -1 | cut -d',' -f4)
        
        if [ -n "$current_battery" ] && [ "$current_battery" != "" ]; then
            # Simulate what we predicted 6 hours ago vs current actual
            local predicted_6h=$(echo "scale=1; $current_battery + $(echo "$RANDOM % 20 - 10" | bc)" | bc)
            local predicted_12h=$(echo "scale=1; $predicted_6h - 2" | bc)
            local predicted_24h=$(echo "scale=1; $predicted_12h - 4" | bc)
            
            # Calculate simulated errors (usually within ±5%)
            local error_6h=$(echo "scale=1; $predicted_6h - $current_battery" | bc)
            local error_12h=$(echo "scale=1; $predicted_12h - $current_battery" | bc) 
            local error_24h=$(echo "scale=1; $predicted_24h - $current_battery" | bc)
            
            # Add to accuracy log
            echo "$test_time,$node,$pred_time,$predicted_6h,$current_battery,$predicted_12h,$current_battery,$predicted_24h,$current_battery,$error_6h,$error_12h,$error_24h,clear sky" >> "$ACCURACY_LOG"
            
            echo "Added test data for $node: Predicted ${predicted_6h}%, Actual ${current_battery}%, Error: ${error_6h}%"
        fi
    done
    
    echo "Simulation complete. Run './ml_power_predictor.sh report' to see results."
}

# Show current ML learning status
show_status() {
    echo "=== ML Power Predictor Learning Status ==="
    echo "Generated: $(date)"
    echo
    
    # Check files exist
    if [ ! -f "$PREDICTIONS_LOG" ]; then
        echo "❌ No predictions file found. Run './ml_power_predictor.sh init' first."
        return 1
    fi
    
    if [ ! -f "$ACCURACY_LOG" ]; then
        echo "❌ No accuracy log found. ML system needs time to collect data."
        echo "   You can simulate data with: $0 simulate"
        return 1
    fi
    
    # Count predictions and accuracy checks
    local total_predictions=$(tail -n +2 "$PREDICTIONS_LOG" | wc -l)
    local total_accuracy_checks=$(tail -n +2 "$ACCURACY_LOG" | wc -l)
    local nodes_tracked=$(tail -n +2 "$PREDICTIONS_LOG" | cut -d',' -f2 | sort -u | wc -l)
    
    echo "📊 Current Status:"
    echo "   Predictions Made: $total_predictions"
    echo "   Accuracy Checks: $total_accuracy_checks"
    echo "   Nodes Tracked: $nodes_tracked"
    echo
    
    if [ "$total_accuracy_checks" -gt 0 ]; then
        echo "🎯 Learning Progress:"
        echo "   Node ID          | Avg Error | Predictions | Latest Error"
        echo "   -----------------|-----------|-------------|-------------"
        
        tail -n +2 "$ACCURACY_LOG" | cut -d',' -f2 | sort -u | while read node_id; do
            local node_accuracy=$(grep ",$node_id," "$ACCURACY_LOG")
            local count=$(echo "$node_accuracy" | wc -l)
            local avg_error=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {
                if($10!="") {
                    err = ($10 < 0 ? -$10 : $10)
                    sum += err
                    count++
                }
            } END{
                if(count>0) printf "%.1f%%", sum/count
                else print "N/A"
            }')
            local latest_error=$(echo "$node_accuracy" | tail -1 | cut -d',' -f10)
            printf "   %-16s | %-9s | %-11d | %s\n" "$node_id" "$avg_error" "$count" "${latest_error}%"
        done
        echo
        
        echo "📈 Recent Activity:"
        tail -3 "$ACCURACY_LOG" | while IFS=',' read -r timestamp node_id pred_time predicted_6h actual_6h predicted_12h actual_12h predicted_24h actual_24h error_6h error_12h error_24h weather; do
            if [ "$timestamp" != "timestamp" ]; then
                echo "   $(date -d "$timestamp" '+%m-%d %H:%M'): $node_id predicted ${predicted_6h}%, actual ${actual_6h}% (${error_6h}% error)"
            fi
        done
    else
        echo "🔄 System is learning... No accuracy data yet."
        echo "   Predictions need 6+ hours to be validated against actual measurements."
    fi
    
    echo
    echo "💡 Next Steps:"
    echo "   - Check HTML dashboard: file://$(pwd)/stats.html"
    echo "   - View detailed report: ./ml_power_predictor.sh report"
    echo "   - Generate new predictions: ./ml_power_predictor.sh predict"
}

# Main execution
case "${1:-status}" in
    "simulate")
        simulate_accuracy_data
        ;;
    "status"|"")
        show_status
        ;;
    "test")
        echo "Testing ML integration..."
        ./ml_power_predictor.sh run
        show_status
        ;;
    *)
        echo "Usage: $0 [simulate|status|test]"
        echo "  simulate - Create test accuracy data for demonstration"
        echo "  status   - Show current ML learning status (default)"
        echo "  test     - Run ML system and show status"
        ;;
esac
