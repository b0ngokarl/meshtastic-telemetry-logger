#!/bin/bash

TELEMETRY_CSV="telemetry_log.csv"
NODES_LOG="nodes_log.txt"
NODES_CSV="nodes_log.csv"
STATS_HTML="stats.html"
ADDRESSES=('!9eed0410' '!2df67288')

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

generate_stats_html
