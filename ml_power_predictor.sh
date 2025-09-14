#!/bin/bash

# Machine Learning Power Predictor for Meshtastic Telemetry Logger
# This script learns from historical data to improve power predictions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TELEMETRY_LOG="$SCRIPT_DIR/telemetry_log.csv"
WEATHER_CACHE="$SCRIPT_DIR/weather_cache"
PREDICTIONS_LOG="$SCRIPT_DIR/power_predictions.csv"
ACCURACY_LOG="$SCRIPT_DIR/prediction_accuracy.csv"
ML_MODEL_DATA="$SCRIPT_DIR/ml_model_data.json"

# Initialize prediction accuracy log
initialize_accuracy_log() {
    if [[ ! -f "$ACCURACY_LOG" ]]; then
        echo "timestamp,node_id,prediction_time,predicted_6h,actual_6h,predicted_12h,actual_12h,predicted_24h,actual_24h,error_6h,error_12h,error_24h,weather_conditions" > "$ACCURACY_LOG"
    fi
}

# Initialize power predictions log
initialize_predictions_log() {
    if [[ ! -f "$PREDICTIONS_LOG" ]]; then
        echo "timestamp,node_id,current_battery,predicted_6h,predicted_12h,predicted_24h,weather_desc,cloud_cover,solar_efficiency" > "$PREDICTIONS_LOG"
    fi
}

# Extract features from historical data for machine learning
extract_features() {
    local node_id="$1"
    local timestamp="$2"
    
    # Use configurable historical window size
    local historical_window=${ML_HISTORICAL_WINDOW:-50}
    
    # Get historical battery levels for this node
    local historical_data=$(grep "^[^,]*,$node_id,success" "$TELEMETRY_LOG" | tail -"$historical_window")
    
    # Calculate battery trends
    local battery_trend=$(echo "$historical_data" | awk -F',' '
        BEGIN { count=0; sum_diff=0 }
        NR > 1 { 
            if (prev_battery != "" && $4 != "") {
                diff = $4 - prev_battery
                sum_diff += diff
                count++
            }
            prev_battery = $4
        }
        END { 
            if (count > 0) print sum_diff/count
            else print 0
        }
    ')
    
    # Get time of day (affects solar generation)
    local hour=$(date -d "$timestamp" +%H)
    local time_factor
    if [[ $hour -ge 6 && $hour -le 18 ]]; then
        # Daylight hours - calculate solar potential
        if [[ $hour -ge 10 && $hour -le 14 ]]; then
            time_factor=1.0  # Peak solar hours
        elif [[ $hour -ge 8 && $hour -le 16 ]]; then
            time_factor=0.7  # Good solar hours
        else
            time_factor=0.3  # Low solar hours
        fi
    else
        time_factor=0.0  # Night time
    fi
    
    # Get weather data
    local lat lon
    lat=$(get_node_location "$node_id" | cut -d',' -f1)
    lon=$(get_node_location "$node_id" | cut -d',' -f2)
    
    local weather_data=""
    if [[ -n "$lat" && -n "$lon" ]]; then
        local weather_file="$WEATHER_CACHE/weather_${lat}_${lon}.json"
        if [[ -f "$weather_file" ]]; then
            weather_data=$(cat "$weather_file")
        fi
    fi
    
    echo "$battery_trend,$time_factor,$weather_data"
}

# Get node location from nodes_log.csv
get_node_location() {
    local node_id="$1"
    grep "^[^,]*,$node_id," "$SCRIPT_DIR/nodes_log.csv" | tail -1 | cut -d',' -f4,5
}

# Calculate improved power prediction using ML
calculate_ml_prediction() {
    local node_id="$1"
    local current_battery="$2"
    local hours="$3"
    local weather_data="$4"
    
    # Load historical accuracy data for this node
    local node_accuracy=$(grep ",$node_id," "$ACCURACY_LOG" 2>/dev/null | tail -10)
    
    # Calculate historical prediction bias
    local bias_6h bias_12h bias_24h
    if [[ -n "$node_accuracy" ]]; then
        bias_6h=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {if($10!="") {sum+=$10; count++}} END{if(count>0) print sum/count; else print 0}')
        bias_12h=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {if($11!="") {sum+=$11; count++}} END{if(count>0) print sum/count; else print 0}')
        bias_24h=$(echo "$node_accuracy" | awk -F',' 'BEGIN{sum=0;count=0} {if($12!="") {sum+=$12; count++}} END{if(count>0) print sum/count; else print 0}')
    else
        bias_6h=0
        bias_12h=0
        bias_24h=0
    fi
    
    # Extract weather features
    local cloud_cover="50"
    local weather_desc="unknown"
    if [[ -n "$weather_data" ]]; then
        cloud_cover=$(echo "$weather_data" | jq -r '.clouds.all // 50' 2>/dev/null || echo "50")
        weather_desc=$(echo "$weather_data" | jq -r '.weather[0].description // "unknown"' 2>/dev/null || echo "unknown")
    fi
    
    # Calculate base prediction using original algorithm
    local base_prediction
    case $hours in
        6)  base_prediction=$(calculate_base_prediction "$current_battery" 6 "$cloud_cover") ;;
        12) base_prediction=$(calculate_base_prediction "$current_battery" 12 "$cloud_cover") ;;
        24) base_prediction=$(calculate_base_prediction "$current_battery" 24 "$cloud_cover") ;;
    esac
    
    # Apply ML correction based on historical bias
    local corrected_prediction
    case $hours in
        6)  corrected_prediction=$(echo "$base_prediction - $bias_6h" | bc -l) ;;
        12) corrected_prediction=$(echo "$base_prediction - $bias_12h" | bc -l) ;;
        24) corrected_prediction=$(echo "$base_prediction - $bias_24h" | bc -l) ;;
    esac
    
    # Ensure prediction is within reasonable bounds
    if (( $(echo "$corrected_prediction < 0" | bc -l) )); then
        corrected_prediction=0
    elif (( $(echo "$corrected_prediction > 100" | bc -l) )); then
        corrected_prediction=100
    fi
    
    echo "$corrected_prediction"
}

# Calculate base prediction (original algorithm)
calculate_base_prediction() {
    local current_battery="$1"
    local hours="$2"
    local cloud_cover="$3"
    
    # Solar efficiency based on cloud cover
    local solar_efficiency=$(echo "scale=2; (100 - $cloud_cover) / 100" | bc -l)
    
    # Base consumption rate (% per hour)
    local base_consumption=1.5
    
    # Solar generation rate during daylight (% per hour)
    local solar_generation=$(echo "scale=2; 3.0 * $solar_efficiency" | bc -l)
    
    # Calculate daylight hours in the prediction period
    local current_hour=$(date +%H)
    local daylight_hours=0
    
    for (( h=0; h<hours; h++ )); do
        local future_hour=$(( (current_hour + h) % 24 ))
        if [[ $future_hour -ge 6 && $future_hour -le 18 ]]; then
            daylight_hours=$((daylight_hours + 1))
        fi
    done
    
    # Calculate net change
    local total_consumption=$(echo "scale=2; $base_consumption * $hours" | bc -l)
    local total_generation=$(echo "scale=2; $solar_generation * $daylight_hours" | bc -l)
    local net_change=$(echo "scale=2; $total_generation - $total_consumption" | bc -l)
    
    # Calculate predicted battery level
    local predicted=$(echo "scale=1; $current_battery + $net_change" | bc -l)
    
    # Ensure bounds
    if (( $(echo "$predicted < 0" | bc -l) )); then
        predicted=0
    elif (( $(echo "$predicted > 100" | bc -l) )); then
        predicted=100
    fi
    
    echo "$predicted"
}

# Log a power prediction
log_prediction() {
    local timestamp="$1"
    local node_id="$2"
    local current_battery="$3"
    local pred_6h="$4"
    local pred_12h="$5"
    local pred_24h="$6"
    local weather_desc="$7"
    local cloud_cover="$8"
    local solar_efficiency="$9"
    
    echo "$timestamp,$node_id,$current_battery,$pred_6h,$pred_12h,$pred_24h,$weather_desc,$cloud_cover,$solar_efficiency" >> "$PREDICTIONS_LOG"
}

# Check prediction accuracy against actual measurements
check_prediction_accuracy() {
    local current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Look for predictions made 6, 12, and 24 hours ago
    local check_times=(
        "$(date -u -d '6 hours ago' +%Y-%m-%dT%H)"
        "$(date -u -d '12 hours ago' +%Y-%m-%dT%H)"
        "$(date -u -d '24 hours ago' +%Y-%m-%dT%H)"
    )
    
    for time_ago in "${check_times[@]}"; do
        local hours_diff
        case "$time_ago" in
            *"$(date -u -d '6 hours ago' +%Y-%m-%dT%H)"*) hours_diff=6 ;;
            *"$(date -u -d '12 hours ago' +%Y-%m-%dT%H)"*) hours_diff=12 ;;
            *"$(date -u -d '24 hours ago' +%Y-%m-%dT%H)"*) hours_diff=24 ;;
        esac
        
        # Find predictions from that time
        grep "^$time_ago" "$PREDICTIONS_LOG" 2>/dev/null | while IFS=',' read -r pred_time node_id old_battery pred_6h pred_12h pred_24h weather_desc cloud_cover solar_eff; do
            # Get current actual battery level
            local actual_battery=$(grep ",$node_id,success" "$TELEMETRY_LOG" | tail -1 | cut -d',' -f4)
            
            if [[ -n "$actual_battery" && "$actual_battery" != "" ]]; then
                # Cap actual battery at 100% for accuracy calculations
                if (( $(echo "$actual_battery > 100" | bc -l 2>/dev/null) )); then
                    actual_battery=100
                fi
                local predicted_value
                case $hours_diff in
                    6)  predicted_value="$pred_6h" ;;
                    12) predicted_value="$pred_12h" ;;
                    24) predicted_value="$pred_24h" ;;
                esac
                
                # Calculate error
                local error=$(echo "scale=2; $predicted_value - $actual_battery" | bc -l)
                
                # Log accuracy data
                echo "$current_time,$node_id,$pred_time,$pred_6h,$actual_battery,$pred_12h,$actual_battery,$pred_24h,$actual_battery,$error,$error,$error,$weather_desc" >> "$ACCURACY_LOG"
                
                echo "[ML] Prediction accuracy for $node_id: Predicted ${predicted_value}% (${hours_diff}h ago), Actual ${actual_battery}%, Error: ${error}%"
            fi
        done
    done
}

# Generate improved predictions for all nodes
generate_ml_predictions() {
    local current_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Process each node with recent telemetry data
    grep ",success," "$TELEMETRY_LOG" | tail -20 | cut -d',' -f2 | sort -u | while read -r node_id; do
        # Get latest battery level
        local latest_data=$(grep ",$node_id,success" "$TELEMETRY_LOG" | tail -1)
        local current_battery=$(echo "$latest_data" | cut -d',' -f4)
        
        if [[ -n "$current_battery" && "$current_battery" != "" ]]; then
            # Cap battery at 100% - treat 101%+ as fully charged
            if (( $(echo "$current_battery > 100" | bc -l 2>/dev/null) )); then
                current_battery=100
            fi
            # Get node location and weather
            local location=$(get_node_location "$node_id")
            local lat=$(echo "$location" | cut -d',' -f1)
            local lon=$(echo "$location" | cut -d',' -f2)
            
            local weather_data=""
            local weather_desc="unknown"
            local cloud_cover="50"
            
            if [[ -n "$lat" && -n "$lon" ]]; then
                local weather_file="$WEATHER_CACHE/weather_${lat}_${lon}.json"
                if [[ -f "$weather_file" ]]; then
                    weather_data=$(cat "$weather_file")
                    weather_desc=$(echo "$weather_data" | jq -r '.weather[0].description // "unknown"' 2>/dev/null || echo "unknown")
                    cloud_cover=$(echo "$weather_data" | jq -r '.clouds.all // 50' 2>/dev/null || echo "50")
                fi
            fi
            
            # Generate ML-improved predictions
            local pred_6h=$(calculate_ml_prediction "$node_id" "$current_battery" 6 "$weather_data")
            local pred_12h=$(calculate_ml_prediction "$node_id" "$current_battery" 12 "$weather_data")
            local pred_24h=$(calculate_ml_prediction "$node_id" "$current_battery" 24 "$weather_data")
            
            # Calculate solar efficiency
            local solar_efficiency=$(echo "scale=2; (100 - $cloud_cover) / 100" | bc -l)
            
            # Log the prediction
            log_prediction "$current_time" "$node_id" "$current_battery" "$pred_6h" "$pred_12h" "$pred_24h" "$weather_desc" "$cloud_cover" "$solar_efficiency"
            
            echo "[ML] Node $node_id: Current ${current_battery}% → 6h: ${pred_6h}%, 12h: ${pred_12h}%, 24h: ${pred_24h}% (${weather_desc}, ${cloud_cover}% clouds)"
        fi
    done
}

# Update the weather predictions JSON with ML predictions
update_weather_predictions_with_ml() {
    local weather_pred_file="$SCRIPT_DIR/weather_predictions.json"
    local temp_file=$(mktemp)
    
    if [[ -f "$weather_pred_file" ]]; then
        # Read the existing predictions and enhance with ML data
        jq --arg current_time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .generated = $current_time |
        .predictions[] |= (
            .ml_predictions = {
                "power_6h": "calculating...",
                "power_12h": "calculating...", 
                "power_24h": "calculating...",
                "accuracy_score": "learning...",
                "last_error_6h": "N/A",
                "last_error_12h": "N/A",
                "last_error_24h": "N/A"
            }
        )' "$weather_pred_file" > "$temp_file"
        
        # Update with actual ML predictions
        while IFS=',' read -r timestamp node_id current_battery pred_6h pred_12h pred_24h weather_desc cloud_cover solar_eff; do
            if [[ "$timestamp" != "timestamp" ]]; then
                # Get latest accuracy data for this node
                local accuracy_data=$(grep ",$node_id," "$ACCURACY_LOG" 2>/dev/null | tail -1)
                local last_error_6h="N/A"
                local last_error_12h="N/A" 
                local last_error_24h="N/A"
                
                if [[ -n "$accuracy_data" ]]; then
                    last_error_6h=$(echo "$accuracy_data" | cut -d',' -f10)
                    last_error_12h=$(echo "$accuracy_data" | cut -d',' -f11)
                    last_error_24h=$(echo "$accuracy_data" | cut -d',' -f12)
                fi
                
                # Calculate accuracy score (inverse of average absolute error)
                local avg_error=$(echo "$accuracy_data" | awk -F',' '{
                    err6 = ($10 < 0 ? -$10 : $10)
                    err12 = ($11 < 0 ? -$11 : $11) 
                    err24 = ($12 < 0 ? -$12 : $12)
                    avg = (err6 + err12 + err24) / 3
                    accuracy = 100 - avg
                    if (accuracy < 0) accuracy = 0
                    printf "%.1f", accuracy
                }')
                
                [[ -z "$avg_error" ]] && avg_error="learning"
                
                # Update JSON with ML predictions
                jq --arg node_id "$node_id" \
                   --arg pred_6h "$pred_6h" \
                   --arg pred_12h "$pred_12h" \
                   --arg pred_24h "$pred_24h" \
                   --arg accuracy "$avg_error" \
                   --arg err_6h "$last_error_6h" \
                   --arg err_12h "$last_error_12h" \
                   --arg err_24h "$last_error_24h" \
                   '(.predictions[] | select(.node_id == $node_id) | .ml_predictions) = {
                       "power_6h": ($pred_6h + "%"),
                       "power_12h": ($pred_12h + "%"),
                       "power_24h": ($pred_24h + "%"),
                       "accuracy_score": ($accuracy + "%"),
                       "last_error_6h": $err_6h,
                       "last_error_12h": $err_12h,
                       "last_error_24h": $err_24h
                   }' "$temp_file" > "${temp_file}.tmp" && mv "${temp_file}.tmp" "$temp_file"
            fi
        done < "$PREDICTIONS_LOG"
        
        mv "$temp_file" "$weather_pred_file"
    fi
}

# Generate accuracy report
generate_accuracy_report() {
    echo "=== Machine Learning Power Prediction Accuracy Report ==="
    echo "Generated: $(date)"
    echo
    
    if [[ ! -f "$ACCURACY_LOG" ]] || [[ ! -s "$ACCURACY_LOG" ]]; then
        echo "No accuracy data available yet. Predictions need time to be validated."
        return
    fi
    
    echo "Node Performance Summary:"
    echo "------------------------"
    
    # Calculate accuracy per node
    tail -n +2 "$ACCURACY_LOG" | cut -d',' -f2 | sort -u | while read -r node_id; do
        local node_data=$(grep ",$node_id," "$ACCURACY_LOG")
        local count=$(echo "$node_data" | wc -l)
        
        if [[ $count -gt 0 ]]; then
            local avg_error_6h=$(echo "$node_data" | awk -F',' 'BEGIN{sum=0;count=0} {if($10!="") {sum+=($10<0?-$10:$10); count++}} END{if(count>0) printf "%.1f", sum/count; else print "N/A"}')
            local avg_error_12h=$(echo "$node_data" | awk -F',' 'BEGIN{sum=0;count=0} {if($11!="") {sum+=($11<0?-$11:$11); count++}} END{if(count>0) printf "%.1f", sum/count; else print "N/A"}')
            local avg_error_24h=$(echo "$node_data" | awk -F',' 'BEGIN{sum=0;count=0} {if($12!="") {sum+=($12<0?-$12:$12); count++}} END{if(count>0) printf "%.1f", sum/count; else print "N/A"}')
            
            echo "$node_id: 6h avg error: ${avg_error_6h}%, 12h avg error: ${avg_error_12h}%, 24h avg error: ${avg_error_24h}% (${count} predictions)"
        fi
    done
    
    echo
    echo "Recent Predictions vs Actual:"
    echo "----------------------------"
    tail -5 "$ACCURACY_LOG" | while IFS=',' read -r timestamp node_id pred_time predicted_6h actual_6h predicted_12h actual_12h predicted_24h actual_24h error_6h error_12h error_24h weather; do
        if [[ "$timestamp" != "timestamp" ]]; then
            echo "$(date -d "$timestamp" '+%m-%d %H:%M') $node_id: 6h: ${predicted_6h}%→${actual_6h}% (${error_6h}%), Weather: $weather"
        fi
    done
}

# Main execution
main() {
    case "${1:-run}" in
        "init")
            echo "Initializing ML Power Predictor..."
            initialize_accuracy_log
            initialize_predictions_log
            echo "ML system initialized."
            ;;
        "predict")
            echo "Generating ML-improved power predictions..."
            initialize_predictions_log
            generate_ml_predictions
            ;;
        "check")
            echo "Checking prediction accuracy..."
            initialize_accuracy_log
            check_prediction_accuracy
            ;;
        "report")
            generate_accuracy_report
            ;;
        "update")
            echo "Updating weather predictions with ML data..."
            update_weather_predictions_with_ml
            ;;
        "run")
            echo "Running full ML prediction cycle..."
            initialize_accuracy_log
            initialize_predictions_log
            check_prediction_accuracy
            generate_ml_predictions
            update_weather_predictions_with_ml
            echo "ML cycle complete."
            ;;
        *)
            echo "Usage: $0 [init|predict|check|report|update|run]"
            echo "  init    - Initialize ML system"
            echo "  predict - Generate ML predictions"
            echo "  check   - Check prediction accuracy"
            echo "  report  - Generate accuracy report"
            echo "  update  - Update weather predictions with ML data"
            echo "  run     - Run full cycle (default)"
            ;;
    esac
}

main "$@"
