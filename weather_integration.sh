#!/bin/bash

# Weather integration script for solar power predictions
# Provides enhanced solar efficiency calculations with astronomical accuracy

# Configuration with better defaults
WEATHER_API_KEY="${WEATHER_API_KEY:-}"
WEATHER_CACHE_DIR="${WEATHER_CACHE_DIR:-/tmp/weather_cache}"
WEATHER_CACHE_TTL="${WEATHER_CACHE_TTL:-3600}"  # Use configurable TTL, default 1 hour
mkdir -p "$WEATHER_CACHE_DIR"

# Default coordinates (from environment or Frankfurt, Germany)
DEFAULT_LAT=${DEFAULT_LATITUDE:-50.1109}
DEFAULT_LON=${DEFAULT_LONGITUDE:-8.6821}

# File for saving predictions
PREDICTIONS_FILE="weather_predictions.json"

# Calculate astronomical sunrise and sunset times
calculate_sunrise_sunset() {
    local lat="$1"
    local lon="$2"
    local day_of_year="${3:-$(date +%j)}"
    
    # Sanitize coordinates - remove any non-numeric characters except decimal point and minus sign
    lat=$(echo "$lat" | sed 's/[^0-9.-]//g')
    lon=$(echo "$lon" | sed 's/[^0-9.-]//g')
    
    # Handle empty strings after sanitization
    if [ -z "$lat" ] || [ -z "$lon" ]; then
        return 1
    fi
    
    # Validate coordinates are proper numbers
    if ! [[ "$lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$lon" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        return 1
    fi
    
    # Validate coordinate ranges
    if (( $(echo "$lat < -90 || $lat > 90" | bc -l 2>/dev/null) )) || (( $(echo "$lon < -180 || $lon > 180" | bc -l 2>/dev/null) )); then
        return 1
    fi
    
    # Astronomical calculations for sunrise/sunset
    # Based on solar angle calculations
    
    # Solar declination angle (in degrees)
    local declination=$(echo "scale=6; 23.45 * s((284 + $day_of_year) * 3.14159/180 * 365.25/365)" | bc -l)
    
    # Hour angle for sunrise/sunset
    local lat_rad=$(echo "scale=6; $lat * 3.14159/180" | bc -l)
    local decl_rad=$(echo "scale=6; $declination * 3.14159/180" | bc -l)
    
    # Hour angle calculation
    local cos_hour_angle=$(echo "scale=6; -1 * (s($lat_rad) * s($decl_rad)) / (c($lat_rad) * c($decl_rad))" | bc -l)
    
    # Check for polar day/night conditions
    local hour_angle_deg
    if (( $(echo "$cos_hour_angle > 1" | bc -l) )); then
        # Polar night
        hour_angle_deg=0
    elif (( $(echo "$cos_hour_angle < -1" | bc -l) )); then
        # Polar day
        hour_angle_deg=180
    else
        hour_angle_deg=$(echo "scale=6; a(sqrt(1 - $cos_hour_angle^2) / $cos_hour_angle) * 180/3.14159" | bc -l)
        if (( $(echo "$hour_angle_deg < 0" | bc -l) )); then
            hour_angle_deg=$(echo "180 + $hour_angle_deg" | bc -l)
        fi
    fi
    
    # Calculate sunrise and sunset times
    local solar_noon=12
    local sunrise_time=$(echo "scale=2; $solar_noon - $hour_angle_deg/15" | bc -l)
    local sunset_time=$(echo "scale=2; $solar_noon + $hour_angle_deg/15" | bc -l)
    
    # Apply longitude correction (rough approximation)
    local lon_correction=$(echo "scale=2; $lon/15" | bc -l)
    sunrise_time=$(echo "scale=2; $sunrise_time - $lon_correction" | bc -l)
    sunset_time=$(echo "scale=2; $sunset_time - $lon_correction" | bc -l)
    
    # Convert to hours and minutes
    local sunrise_hour=$(echo "$sunrise_time" | cut -d. -f1)
    local sunset_hour=$(echo "$sunset_time" | cut -d. -f1)
    local sunrise_min=$(echo "scale=0; ($sunrise_time - $sunrise_hour) * 60" | bc -l)
    local sunset_min=$(echo "scale=0; ($sunset_time - $sunset_hour) * 60" | bc -l)
    
    # Clamp values to valid ranges
    sunrise_hour=$(echo "$sunrise_hour" | awk '{printf "%d", ($1 < 0) ? 0 : ($1 > 23) ? 23 : $1}')
    sunset_hour=$(echo "$sunset_hour" | awk '{printf "%d", ($1 < 0) ? 0 : ($1 > 23) ? 23 : $1}')
    sunrise_min=$(echo "$sunrise_min" | awk '{printf "%02d", ($1 < 0) ? 0 : ($1 > 59) ? 59 : $1}')
    sunset_min=$(echo "$sunset_min" | awk '{printf "%02d", ($1 < 0) ? 0 : ($1 > 59) ? 59 : $1}')
    
    echo "${sunrise_hour}:${sunrise_min}:${sunset_hour}:${sunset_min}"
}

# Get weather data from API or cache
get_weather_data() {
    local lat="$1"
    local lon="$2"
    
    local cache_file="${WEATHER_CACHE_DIR}/weather_${lat}_${lon}.json"
    
    # Check cache with configurable TTL
    if [[ -f "$cache_file" ]] && [[ $(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0))) -lt $WEATHER_CACHE_TTL ]]; then
        cat "$cache_file"
        return 0
    fi
    
    if [[ -n "$WEATHER_API_KEY" ]]; then
        local weather_url="https://api.openweathermap.org/data/2.5/forecast?lat=${lat}&lon=${lon}&appid=${WEATHER_API_KEY}&units=metric"
        
        if curl -s "$weather_url" > "$cache_file.tmp"; then
            mv "$cache_file.tmp" "$cache_file"
            cat "$cache_file"
        else
            echo "Error: Failed to fetch weather data" >&2
            generate_mock_weather "$lat" "$lon"
        fi
    else
        generate_mock_weather "$lat" "$lon"
    fi
}

# Generate mock weather data when API is not available
generate_mock_weather() {
    local lat="$1"
    local lon="$2"
    
    cat << EOF
{
    "list": [
        {
            "dt": $(date +%s),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 3)) -eq 0 ] && echo "Clouds" || echo "Clear")", "description": "scattered clouds"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date '+%Y-%m-%d %H:%M:%S')"
        },
        {
            "dt": $(($(date +%s) + 21600)),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 3)) -eq 0 ] && echo "Clouds" || echo "Clear")", "description": "scattered clouds"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date -d '+6 hours' '+%Y-%m-%d %H:%M:%S')"
        },
        {
            "dt": $(($(date +%s) + 43200)),
            "main": {"temp": $((15 + RANDOM % 15))},
            "weather": [{"main": "$([ $((RANDOM % 3)) -eq 0 ] && echo "Clouds" || echo "Clear")", "description": "scattered clouds"}],
            "clouds": {"all": $((RANDOM % 100))},
            "dt_txt": "$(date -d '+12 hours' '+%Y-%m-%d %H:%M:%S')"
        }
    ]
}
EOF
}

# Calculate solar efficiency based on weather and sun position
calculate_solar_efficiency() {
    local lat="$1"
    local lon="$2"
    local hour="$3"
    local clouds="$4"
    local temp="$5"
    
    # Sanitize coordinates - remove any non-numeric characters except decimal point and minus sign
    lat=$(echo "$lat" | sed 's/[^0-9.-]//g')
    lon=$(echo "$lon" | sed 's/[^0-9.-]//g')
    
    # Validate inputs
    if [[ ! "$lat" =~ ^-?[0-9]+\.?[0-9]*$ ]] || [[ ! "$lon" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "0"  # Return 0% efficiency for invalid coordinates
        return
    fi
    
    if [[ ! "$hour" =~ ^[0-9]+\.?[0-9]*$ ]] || [[ ! "$clouds" =~ ^[0-9]+\.?[0-9]*$ ]] || [[ ! "$temp" =~ ^-?[0-9]+\.?[0-9]*$ ]]; then
        echo "0"  # Return 0% efficiency for invalid inputs
        return
    fi
    
    # Simple sunrise/sunset calculation (approximation)
    # For most locations, assume sunrise around 6:00 and sunset around 18:00 with seasonal variation
    local day_of_year=$(date +%j)
    local sunrise_hour=6
    local sunset_hour=18
    
    # Adjust for seasonal variation (rough approximation)
    local seasonal_adjustment=$(echo "scale=2; 2 * s((${day_of_year} - 81) * 3.14159 / 182.5)" | bc -l 2>/dev/null || echo "0")
    sunrise_hour=$(echo "scale=2; $sunrise_hour - $seasonal_adjustment" | bc -l 2>/dev/null || echo "6")
    sunset_hour=$(echo "scale=2; $sunset_hour + $seasonal_adjustment" | bc -l 2>/dev/null || echo "18")
    
    # Check if it's daylight
    if (( $(echo "$hour < $sunrise_hour || $hour > $sunset_hour" | bc -l 2>/dev/null || echo "1") )); then
        echo "0"
        return
    fi
    
    # Calculate sun elevation angle (simplified)
    local solar_noon=12
    local hour_angle=$(echo "scale=6; ($hour - $solar_noon) * 15" | bc -l 2>/dev/null || echo "0")
    
    # Simple elevation calculation based on hour angle
    local elevation_factor
    if (( $(echo "$hour_angle < -90 || $hour_angle > 90" | bc -l 2>/dev/null || echo "0") )); then
        elevation_factor=0
    else
        # Use cosine of hour angle as approximation for sun elevation
        elevation_factor=$(echo "scale=6; c($hour_angle * 3.14159 / 180)" | bc -l 2>/dev/null || echo "0")
        if (( $(echo "$elevation_factor < 0" | bc -l 2>/dev/null || echo "0") )); then
            elevation_factor=0
        fi
    fi
    
    # Base efficiency from sun angle (0-100%)
    local sun_efficiency=$(echo "scale=2; $elevation_factor * 80" | bc -l 2>/dev/null || echo "0")
    
    # Cloud factor (0-100% clouds reduces efficiency)
    local cloud_factor=$(echo "scale=2; (100 - $clouds) / 100" | bc -l 2>/dev/null || echo "0.5")
    
    # Temperature factor (optimal around 25C, efficiency decreases in extreme heat)
    local temp_factor=1
    if (( $(echo "$temp > 25" | bc -l 2>/dev/null || echo "0") )); then
        temp_factor=$(echo "scale=2; 1 - ($temp - 25) * 0.004" | bc -l 2>/dev/null || echo "1") # 0.4% loss per degree above 25C
    elif (( $(echo "$temp < 0" | bc -l 2>/dev/null || echo "0") )); then
        temp_factor=$(echo "scale=2; 1 + $temp * 0.002" | bc -l 2>/dev/null || echo "1") # slight gain in cold (up to a point)
    fi
    
    # Ensure factors are within reasonable bounds
    if (( $(echo "$temp_factor < 0.5" | bc -l 2>/dev/null || echo "0") )); then
        temp_factor=0.5
    elif (( $(echo "$temp_factor > 1.2" | bc -l 2>/dev/null || echo "0") )); then
        temp_factor=1.2
    fi
    
    # Calculate final efficiency
    local efficiency=$(echo "scale=2; $sun_efficiency * $cloud_factor * $temp_factor" | bc -l 2>/dev/null || echo "0")
    
    # Ensure result is within bounds
    if (( $(echo "$efficiency < 0" | bc -l 2>/dev/null || echo "0") )); then
        efficiency=0
    elif (( $(echo "$efficiency > 100" | bc -l 2>/dev/null || echo "0") )); then
        efficiency=100
    fi
    
    printf "%.1f" "$efficiency"
}

# Predict battery level based on current state and weather
predict_battery_level() {
    local current_battery="$1"
    local solar_efficiency="$2"
    local hours="$3"
    local lat="${4:-$DEFAULT_LAT}"
    local lon="${5:-$DEFAULT_LON}"
    
    # Validate inputs
    if ! [[ "$current_battery" =~ ^[0-9]+\.?[0-9]*$ ]] || ! [[ "$solar_efficiency" =~ ^[0-9]+\.?[0-9]*$ ]] || ! [[ "$hours" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        echo "50.0"  # Default value for invalid inputs
        return
    fi
    
    # Cap battery at 100% if it's over 100%
    if (( $(echo "$current_battery > 100" | bc -l 2>/dev/null || echo "0") )); then
        current_battery=100
    fi
    
    # Base power consumption per hour (assuming 2% per hour average for a typical Meshtastic device)
    local base_consumption=2
    
    # Solar generation factor (efficiency affects how much power is generated)
    # Assume optimal solar panels can generate 5% battery per hour in full sun
    local max_solar_generation=5
    local actual_generation=$(echo "scale=2; $max_solar_generation * $solar_efficiency / 100" | bc -l 2>/dev/null || echo "0")
    
    # Net change per hour
    local net_change=$(echo "scale=2; $actual_generation - $base_consumption" | bc -l 2>/dev/null || echo "-2")
    
    # Calculate predicted battery level
    local predicted=$(echo "scale=2; $current_battery + ($net_change * $hours)" | bc -l 2>/dev/null || echo "$current_battery")
    
    # Ensure battery level stays within 0-100% bounds
    if (( $(echo "$predicted < 0" | bc -l 2>/dev/null || echo "0") )); then
        predicted=0
    elif (( $(echo "$predicted > 100" | bc -l 2>/dev/null || echo "0") )); then
        predicted=100
    fi
    
    printf "%.1f" "$predicted"
}

# Generate comprehensive weather report with predictions
generate_weather_report() {
    local nodes_csv="$1"
    local telemetry_csv="$2"
    local output_file="$3"
    
    echo "Generating enhanced weather-based predictions..."
    
    # Initialize JSON output
    cat > "$output_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "predictions": [
EOF
    
    local first_entry=true
    
    # Process each node from the CSV
    while IFS=',' read -r node_id longname lat lon altitude last_seen battery voltage snr rssi hop_start channel tx_power || [[ -n "$node_id" ]]; do
        # Skip header line
        if [[ "$node_id" == "node_id" ]] || [[ "$node_id" == "User" ]]; then
            continue
        fi
        
        # Skip empty lines
        if [[ -z "$node_id" ]]; then
            continue
        fi
        
        # Remove quotes from all fields
        node_id=$(echo "$node_id" | sed 's/^"//; s/"$//')
        longname=$(echo "$longname" | sed 's/^"//; s/"$//')
        lat=$(echo "$lat" | sed 's/^"//; s/"$//')
        lon=$(echo "$lon" | sed 's/^"//; s/"$//')
        battery=$(echo "$battery" | sed 's/^"//; s/"$//')
        
        # Use default coordinates if not provided or invalid
        lat="${lat:-$DEFAULT_LAT}"
        lon="${lon:-$DEFAULT_LON}"
        battery="${battery:-50}"
        
        # Sanitize coordinates - remove degree symbols and other non-numeric characters except decimal point and minus
        lat=$(echo "$lat" | sed 's/[^0-9.-]//g')
        lon=$(echo "$lon" | sed 's/[^0-9.-]//g')
        
        # Sanitize battery value
        battery=$(echo "$battery" | sed 's/[^0-9.-]//g')
        
        # Validate coordinates and battery
        if [ -z "$lat" ] || [ -z "$lon" ] || [ "$lat" = "N/A" ] || [ "$lon" = "N/A" ] || ! [[ "$lat" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$lon" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Warning: Invalid coordinates for $node_id: lat=$lat, lon=$lon. Using defaults." >&2
            lat="$DEFAULT_LAT"
            lon="$DEFAULT_LON"
        fi
        
        # Additional coordinate range validation
        if (( $(echo "$lat < -90 || $lat > 90 || $lon < -180 || $lon > 180" | bc -l 2>/dev/null || echo "1") )); then
            echo "Warning: Coordinates out of range for $node_id: lat=$lat, lon=$lon. Using defaults." >&2
            lat="$DEFAULT_LAT"
            lon="$DEFAULT_LON"
        fi
        
        if [ -z "$battery" ] || [ "$battery" = "N/A" ] || ! [[ "$battery" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "Warning: Invalid battery for $node_id: $battery. Using 50." >&2
            battery="50"
        fi
        
        echo "Processing node: $node_id at coordinates ($lat, $lon)..."
        
        # Get weather data
        local weather_data=$(get_weather_data "$lat" "$lon")
        
        # Extract weather information for different time periods
        local temp_6h=$(echo "$weather_data" | jq -r '.list[0].main.temp // 20')
        local clouds_6h=$(echo "$weather_data" | jq -r '.list[0].clouds.all // 50')
        local temp_12h=$(echo "$weather_data" | jq -r '.list[1].main.temp // 20')
        local clouds_12h=$(echo "$weather_data" | jq -r '.list[1].clouds.all // 50')
        local temp_24h=$(echo "$weather_data" | jq -r '.list[2].main.temp // 20')
        local clouds_24h=$(echo "$weather_data" | jq -r '.list[2].clouds.all // 50')
        
        # Calculate solar efficiency for different times
        local current_hour=$(date +%H)
        
        # Calculate future hours with 24-hour wrap-around
        local hour_6h=$(( (current_hour + 6) % 24 ))
        local hour_12h=$(( (current_hour + 12) % 24 ))
        local hour_24h=$(( current_hour ))  # Same time tomorrow
        
        local efficiency_6h=$(calculate_solar_efficiency "$lat" "$lon" "$hour_6h" "$clouds_6h" "$temp_6h")
        local efficiency_12h=$(calculate_solar_efficiency "$lat" "$lon" "$hour_12h" "$clouds_12h" "$temp_12h")
        local efficiency_24h=$(calculate_solar_efficiency "$lat" "$lon" "$hour_24h" "$clouds_24h" "$temp_24h")
        
        # Get sunrise/sunset times
        local sun_times=$(calculate_sunrise_sunset "$lat" "$lon")
        local sunrise=$(echo "$sun_times" | cut -d: -f1-2 | tr ':' ':')
        local sunset=$(echo "$sun_times" | cut -d: -f3-4 | tr ':' ':')
        
        # Predict battery levels
        local battery_6h=$(predict_battery_level "$battery" "$efficiency_6h" "6" "$lat" "$lon")
        local battery_12h=$(predict_battery_level "$battery" "$efficiency_12h" "12" "$lat" "$lon")
        local battery_24h=$(predict_battery_level "$battery" "$efficiency_24h" "24" "$lat" "$lon")
        
        # Add comma if not first entry
        if [[ "$first_entry" != true ]]; then
            echo "," >> "$output_file"
        fi
        first_entry=false
        
        # Escape JSON special characters in strings
        node_id_escaped=$(echo "$node_id" | sed 's/\\/\\\\/g; s/"/\\"/g')
        longname_escaped=$(echo "$longname" | sed 's/\\/\\\\/g; s/"/\\"/g')
        
        # Write prediction to JSON
        cat >> "$output_file" << EOF
        {
            "node_id": "$node_id_escaped",
            "longname": "$longname_escaped",
            "coordinates": {
                "lat": $lat,
                "lon": $lon
            },
            "current_battery": $battery,
            "sunrise": "$sunrise",
            "sunset": "$sunset",
            "predictions": {
                "6h": {
                    "battery_level": $battery_6h,
                    "solar_efficiency": $efficiency_6h,
                    "temperature": $temp_6h,
                    "clouds": $clouds_6h
                },
                "12h": {
                    "battery_level": $battery_12h,
                    "solar_efficiency": $efficiency_12h,
                    "temperature": $temp_12h,
                    "clouds": $clouds_12h
                },
                "24h": {
                    "battery_level": $battery_24h,
                    "solar_efficiency": $efficiency_24h,
                    "temperature": $temp_24h,
                    "clouds": $clouds_24h
                }
            }
        }
EOF
        
    done < "$nodes_csv"
    
    # Close JSON
    echo '    ]' >> "$output_file"
    echo '}' >> "$output_file"
    
    echo "Weather predictions saved to $output_file"
}

# Main execution
main() {
    local nodes_csv="${1:-nodes_log.csv}"
    local telemetry_csv="${2:-telemetry_log.csv}"
    local output_file="${3:-$PREDICTIONS_FILE}"
    
    if [[ ! -f "$nodes_csv" ]]; then
        echo "Error: Nodes CSV file not found: $nodes_csv"
        exit 1
    fi
    
    if [[ ! -f "$telemetry_csv" ]]; then
        echo "Warning: Telemetry CSV file not found: $telemetry_csv"
    fi
    
    # Check for required tools
    if ! command -v jq &> /dev/null; then
        echo "Warning: jq not found. Installing jq for JSON processing..."
        sudo apt update && sudo apt install -y jq
    fi
    
    if ! command -v bc &> /dev/null; then
        echo "Warning: bc not found. Installing bc for calculations..."
        sudo apt update && sudo apt install -y bc
    fi
    
    echo "Starting weather integration for solar energy predictions..."
    echo "Note: Set WEATHER_API_KEY for real weather data - currently using mock data"
    
    generate_weather_report "$nodes_csv" "$telemetry_csv" "$output_file"
    
    echo "Weather integration complete!"
    echo "Generated predictions: $output_file"
}

# Run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
