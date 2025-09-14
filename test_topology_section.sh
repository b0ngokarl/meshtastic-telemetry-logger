#!/bin/bash

# Simple test for the topology section
TRACEROUTE_CSV="traceroute_log.csv"

# Create mock environment
export TRACEROUTE_CSV="traceroute_log.csv"

# Simple version of the topology section generation
echo '<div class="network-topology">'
echo '<h3><i class="fas fa-project-diagram"></i> Route Analysis & Network Map</h3>'

if [ ! -f "$TRACEROUTE_CSV" ]; then
    echo '<div class="info-card">'
    echo '<h4><i class="fas fa-info-circle"></i> No Traceroute Data</h4>'
    echo '<p>Traceroute data collection has not been run yet.</p>'
    echo '</div>'
else
    # Check if we have traceroute data
    traceroute_count=$(tail -n +2 "$TRACEROUTE_CSV" 2>/dev/null | wc -l)
    
    if [ "$traceroute_count" -eq 0 ]; then
        echo '<div class="info-card">'
        echo '<h4><i class="fas fa-hourglass-half"></i> Collecting Network Data</h4>'
        echo '<p>Traceroute collection is enabled but no data has been collected yet.</p>'
        echo '</div>'
    else
        # Calculate basic stats
        total_attempts=$(tail -n +2 "$TRACEROUTE_CSV" | wc -l)
        successful_routes=$(tail -n +2 "$TRACEROUTE_CSV" | awk -F',' '$3=="true"' | wc -l)
        success_rate=0
        
        if [ "$total_attempts" -gt 0 ]; then
            success_rate=$(echo "scale=1; $successful_routes * 100 / $total_attempts" | bc 2>/dev/null || echo "0")
        fi
        
        echo '<div class="topology-stats">'
        echo '<h4><i class="fas fa-chart-line"></i> Route Statistics</h4>'
        echo '<div class="stats-grid">'
        echo "  <div class=\"stat-item\">"
        echo "    <span class=\"stat-label\">Total Routes Traced:</span>"
        echo "    <span class=\"stat-value\">$total_attempts</span>"
        echo "  </div>"
        echo "  <div class=\"stat-item\">"
        echo "    <span class=\"stat-label\">Successful Routes:</span>"
        echo "    <span class=\"stat-value\">$successful_routes</span>"
        echo "  </div>"
        echo "  <div class=\"stat-item\">"
        echo "    <span class=\"stat-label\">Route Success Rate:</span>"
        echo "    <span class=\"stat-value\">${success_rate}%</span>"
        echo "  </div>"
        echo '</div>'
        echo '</div>'
        
        # Display SVG if available
        if [ -f "network_topology.svg" ]; then
            echo '<div class="topology-visualization">'
            echo '<h4><i class="fas fa-project-diagram"></i> Network Topology Map</h4>'
            echo '<div class="chart-container">'
            cat "network_topology.svg"
            echo '</div>'
            echo '</div>'
        fi
        
        # Display recent traceroute results
        echo '<div class="recent-traceroutes">'
        echo '<h4><i class="fas fa-route"></i> Recent Traceroute Results</h4>'
        echo '<table class="modern-table">'
        echo '<thead>'
        echo '<tr><th>Timestamp</th><th>Target</th><th>Status</th><th>Hops</th><th>Route Path</th></tr>'
        echo '</thead>'
        echo '<tbody>'
        
        # Show last 5 traceroute results
        tail -5 "$TRACEROUTE_CSV" | tac | while IFS=',' read -r timestamp target success total_hops hops; do
            if [ -n "$timestamp" ]; then
                # Remove quotes from hops field for display
                hops_display=$(echo "$hops" | sed 's/^"//; s/"$//')
                
                case "$success" in
                    "true")
                        status_class="success"
                        status_text="✅ Success"
                        ;;
                    "timeout")
                        status_class="warning"
                        status_text="⏱️ Timeout"
                        ;;
                    "false")
                        status_class="danger"
                        status_text="❌ No Route"
                        ;;
                    *)
                        status_class="secondary"
                        status_text="❓ $success"
                        ;;
                esac
                
                if [ "$hops_display" = "NO_ROUTE" ] || [ "$hops_display" = "TIMEOUT" ] || [ "$hops_display" = "ERROR" ]; then
                    route_display="<em>$hops_display</em>"
                else
                    route_display=$(echo "$hops_display" | sed 's/,/ → /g')
                fi
                
                echo "<tr>"
                echo "<td>$timestamp</td>"
                echo "<td>$target</td>"
                echo "<td class=\"$status_class\">$status_text</td>"
                echo "<td>$total_hops</td>"
                echo "<td>$route_display</td>"
                echo "</tr>"
            fi
        done
        
        echo '</tbody>'
        echo '</table>'
        echo '</div>'
    fi
fi

echo '</div>'
