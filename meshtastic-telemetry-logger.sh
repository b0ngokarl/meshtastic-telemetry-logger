#!/bin/bash

# ---- CONFIGURATION ----
ADDRESSES=('!9eed0410' '!2df67288') # Add/change as needed
INTERVAL=300                        # Polling interval in seconds
TELEMETRY_CSV="telemetry_log.csv"
NODES_LOG="nodes_log.txt"
STATS_HTML="stats.html"
ERROR_LOG="error.log"

# ---- INIT ----
if [ ! -f "$TELEMETRY_CSV" ]; then
    echo "timestamp,address,status,battery,voltage,channel_util,tx_util,uptime" > "$TELEMETRY_CSV"
fi

# ---- FUNCTIONS ----

run_telemetry() {
    local addr="$1"
    local ts
    ts=$(date --iso-8601=seconds)
    local out
    out=$(meshtastic --request-telemetry --dest "'$addr'" 2>&1)
    local status="unknown"
    local battery="" voltage="" channel_util="" tx_util="" uptime=""

    if echo "$out" | grep -q "Telemetry received:"; then
        status="success"
        battery=$(echo "$out" | grep "Battery level:" | awk -F: '{print $2}' | tr -d ' %')
        voltage=$(echo "$out" | grep "Voltage:" | awk -F: '{print $2}' | tr -d ' V')
        channel_util=$(echo "$out" | grep "Total channel utilization:" | awk -F: '{print $2}' | tr -d ' %')
        tx_util=$(echo "$out" | grep "Transmit air utilization:" | awk -F: '{print $2}' | tr -d ' %')
        uptime=$(echo "$out" | grep "Uptime:" | awk -F: '{print $2}' | tr -d ' s')
    elif echo "$out" | grep -q "Timed out waiting for telemetry"; then
        status="timeout"
    else
        status="error"
        echo "$ts [$addr] ERROR: $out" >> "$ERROR_LOG"
    fi

    echo "$ts,$addr,$status,$battery,$voltage,$channel_util,$tx_util,$uptime" >> "$TELEMETRY_CSV"
}

update_nodes_log() {
    local ts
    ts=$(date --iso-8601=seconds)
    local out
    out=$(meshtastic --nodes 2>&1)
    echo "===== $ts =====" >> "$NODES_LOG"
    echo "$out" >> "$NODES_LOG"
}

generate_stats_html() {
    {
        echo "<html><head><title>Meshtastic Telemetry Stats</title></head><body>"
        echo "<h1>Meshtastic Telemetry - Last Results</h1>"
        echo "<table border=1><tr><th>Timestamp</th><th>Address</th><th>Status</th><th>Battery</th><th>Voltage</th><th>Channel Util</th><th>Tx Util</th><th>Uptime</th></tr>"
        tail -n 20 "$TELEMETRY_CSV" | awk -F, 'NR>1 {print "<tr><td>"$1"</td><td>"$2"</td><td>"$3"</td><td>"$4"</td><td>"$5"</td><td>"$6"</td><td>"$7"</td><td>"$8"</td></tr>"}'
        echo "</table>"

        # Simple stats
        echo "<h2>Success Rate</h2><ul>"
        for addr in "${ADDRESSES[@]}"; do
            total=$(grep "$addr" "$TELEMETRY_CSV" | wc -l)
            success=$(grep "$addr" "$TELEMETRY_CSV" | grep "success" | wc -l)
            rate=0
            if [ "$total" -gt 0 ]; then rate=$((100 * success / total)); fi
            echo "<li>$addr: $rate% ($success / $total)</li>"
        done
        echo "</ul>"

        echo "<h2>Node Log Snapshots</h2><pre>"
        tail -n 40 "$NODES_LOG"
        echo "</pre>"

        echo "</body></html>"
    } > "$STATS_HTML"
}

# ---- MAIN LOOP ----
while true; do
    for addr in "${ADDRESSES[@]}"; do
        run_telemetry "$addr"
    done
    update_nodes_log
    generate_stats_html
    sleep "$INTERVAL"
done
