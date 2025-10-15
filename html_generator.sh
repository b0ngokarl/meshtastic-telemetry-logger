#!/bin/bash
# html_generator.sh - Modular Dashboard Generator v7

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"

# --- MODULE: NODE DETAILS TABLE ---
generate_nodes_table() {
    local nodes_csv_file="${1:-$NODES_CSV}"
    if [ ! -f "$nodes_csv_file" ]; then
        echo "<p>Node data file not found.</p>"
        return
    fi

    echo "<div style='overflow-x:auto;'>"
    echo "<table>"
    echo "<thead><tr><th>Node</th><th>ID</th><th>Role</th><th>Last Heard</th><th>Battery</th><th>Voltage</th><th>Success %</th></tr></thead>"
    echo "<tbody>"

    local stats_file
    stats_file=$(compute_telemetry_stats)

    local awk_env_vars=()
    for node_id in "${!NODE_INFO_CACHE[@]}"; do
        local clean_node_id=$(echo "$node_id" | sed 's/!//g')
        awk_env_vars+=("NODE_NAME_${clean_node_id}=${NODE_INFO_CACHE[$node_id]}")
    done

    env "${awk_env_vars[@]}" awk -F, -v stats_file="$stats_file" '
        BEGIN {
            OFS=",";
            while((getline < stats_file) > 0) {
                split($0, a, "|");
                clean_id = a[1]; gsub(/!/, "", clean_id);
                stats[clean_id] = a[5];
                voltages[clean_id] = a[9];
            }
        }
        NR > 1 {
            id_raw = $2; gsub(/"/, "", id_raw);
            id_clean = id_raw; gsub(/!/, "", id_clean);

            friendly_name = ENVIRON["NODE_NAME_" id_clean];
            if (friendly_name == "") friendly_name = $1;
            gsub(/"/, "", friendly_name);
            if (friendly_name == "") friendly_name = id_raw;

            role = $5;
            last_heard = $11;
            battery = $9;
            voltage = voltages[id_clean];
            if (voltage == "" || voltage == "N/A") voltage = "N/A";

            rate = stats[id_clean];
            if (rate == "") rate = 0;

            rate_class = "success-rate-low";
            if (rate > 90) rate_class = "success-rate-good";
            else if (rate > 70) rate_class = "success-rate-medium";

            battery_display = (battery ~ /^[0-9]+(\.[0-9]+)?$/) ? battery "%" : "N/A";
            voltage_display = (voltage != "N/A") ? voltage "V" : "N/A";

            printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><span class=\"%s\">%.1f%%</span></td></tr>\n", friendly_name, id_raw, role, last_heard, battery_display, voltage_display, rate_class, rate;
        }
    ' "$nodes_csv_file"

    echo "</tbody></table>"
    echo "</div>"
    rm -f "$stats_file"
}

# --- MAIN DASHBOARD GENERATOR ---
generate_dashboard_optimized() {
    local html_output_file="${HTML_OUTPUT:-"stats.html"}"
    debug_log "Starting modular dashboard generation v7 (Output: $html_output_file)"

    local nodes_table_html=$(generate_nodes_table)
    local traceroute_data=""
    if [ -f "$ROUTING_LOG_RAW" ]; then
        traceroute_data=$(tail -n +2 "$ROUTING_LOG_RAW" | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')
    fi

    {
        echo "<!DOCTYPE html><html lang='en'><head>"
        echo "<meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'>"
        echo "<meta http-equiv='refresh' content='${POLLING_INTERVAL:-300}'>"
        echo "<title>Meshtastic Network Dashboard</title>"
        echo "<script src='https://unpkg.com/vis-network/standalone/umd/vis-network.min.js'></script>"
        echo "<style>"
        echo "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background-color:#121212;color:#e0e0e0;margin:0;padding:20px}"
        echo ".container{max-width:95%;margin:auto}h1,h2{color:#bb86fc;border-bottom:2px solid #373737;padding-bottom:10px}"
        echo ".grid-container{display:grid;grid-template-columns:repeat(auto-fit,minmax(450px,1fr));gap:20px}"
        echo ".section{background-color:#1e1e1e;padding:20px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.4);transition:transform .2s}.section:hover{transform:translateY(-5px)}"
        echo ".chart-container{text-align:center;margin:20px 0}img.chart{max-width:100%;height:auto;border-radius:8px;background-color:white}"
        echo "#last-updated{text-align:center;color:#a0a0a0;margin-bottom:20px;font-size:.9em}"
        echo "#topology-map{width:100%;height:500px;border:1px solid #373737;border-radius:8px;background-color:#2c2c2c}"
        echo "table{width:100%;border-collapse:collapse;margin-top:15px}th,td{padding:12px;text-align:left;border-bottom:1px solid #373737}th{background-color:#333;color:#bb86fc}tr:nth-child(even){background-color:#2c2c2c}"
        echo ".success-rate-good{color:#81c784;font-weight:bold}.success-rate-medium{color:#ffb74d;font-weight:bold}.success-rate-low{color:#e57373;font-weight:bold}"
        echo "</style></head><body><div class='container'>"
        echo "<h1>Meshtastic Network Dashboard</h1><div id='last-updated'>Last Updated: $(date)</div>"
        echo "<div class='grid-container'>"
        echo "<div class='section' id='activity-section'><h2>Network Activity</h2><div id='network-news-container'><p>Loading network news...</p></div><div class='chart-container' id='utilization-chart-container' style='margin-top: 20px;'><p>Loading utilization chart...</p></div></div>"
        echo "<div class='section' id='comprehensive-chart-section'><h2>Comprehensive Telemetry</h2><div class='chart-container' id='comprehensive-chart-container'><p>Loading chart...</p></div></div>"
        echo "<div class='section' id='nodes-section'><h2>Node Details</h2><div id='nodes-table-container'>$nodes_table_html</div></div>"
        echo "</div>"
        echo "<div class='section' id='topology-section' style='margin-top: 20px;'><h2>Network Topology</h2><div id='topology-map'></div><div id='traceroute-data-container' style='display:none;'>$traceroute_data</div></div>"
        echo "</div>"
        cat <<'EOF'
<script>
document.addEventListener('DOMContentLoaded', function() {
    console.log('Dashboard v7 loaded. Initializing dynamic content...');
    const loadContent = (url, containerId, isChart) => {
        fetch(url)
            .then(response => {
                if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                return response.text();
            })
            .then(data => {
                const container = document.getElementById(containerId);
                if (!container) return;
                if (isChart) {
                    if (data.trim()) {
                        container.innerHTML = `<img src="data:image/svg+xml;base64,${data}" class="chart" alt="Telemetry Chart">`;
                    } else {
                        container.innerHTML = '<p>Chart data is not available.</p>';
                    }
                } else {
                    container.innerHTML = data;
                }
            })
            .catch(e => {
                console.error(`Error loading content for ${containerId}:`, e);
                const container = document.getElementById(containerId);
                if (container) container.innerHTML = '<p>Error loading content.</p>';
            });
    };

    loadContent('network_news.html', 'network-news-container', false);
    loadContent('comprehensive_chart_base64.txt', 'comprehensive-chart-container', true);
    loadContent('utilization_chart_base64.txt', 'utilization-chart-container', true);

    const tracerouteDataEl = document.getElementById('traceroute-data-container');
    const topologyMapEl = document.getElementById('topology-map');

    if (tracerouteDataEl && topologyMapEl && tracerouteDataEl.innerHTML.trim() !== '') {
        try {
            const rawData = tracerouteDataEl.textContent;
            const lines = rawData.split('\n').filter(line => line.trim() !== '');
            const nodes = new vis.DataSet();
            const edges = new vis.DataSet();
            const nodeIds = new Set();

            lines.forEach(line => {
                const parts = line.split(',');
                if (parts.length < 3) return;
                const fromNode = parts[1].trim();
                const toNode = parts[2].trim();
                const routePathStr = parts[3] ? parts[3].replace(/"/g, '') : '';
                const routePath = routePathStr.split(' -> ');

                [fromNode, toNode, ...routePath].forEach(nodeId => {
                    if (nodeId && !nodeIds.has(nodeId)) {
                        nodes.add({ id: nodeId, label: nodeId });
                        nodeIds.add(nodeId);
                    }
                });

                if (routePath.length > 1) {
                    for (let i = 0; i < routePath.length - 1; i++) {
                        const source = routePath[i].trim();
                        const target = routePath[i+1].trim();
                        if (source && target) {
                            const edgeId = `${source}-${target}`;
                            const reverseEdgeId = `${target}-${source}`;
                            if (!edges.get(edgeId) && !edges.get(reverseEdgeId)) {
                                edges.add({ id: edgeId, from: source, to: target, arrows: 'to' });
                            }
                        }
                    }
                } else if (fromNode && toNode && fromNode !== toNode) {
                    const edgeId = `${fromNode}-${toNode}`;
                    const reverseEdgeId = `${toNode}-${fromNode}`;
                    if (!edges.get(edgeId) && !edges.get(reverseEdgeId)) {
                        edges.add({ id: edgeId, from: fromNode, to: toNode, arrows: 'to', dashes: true });
                    }
                }
            });

            const data = { nodes: nodes, edges: edges };
            const options = {
                layout: { improvedLayout: true },
                nodes: {
                    shape: 'box',
                    color: { background: '#bb86fc', border: '#9e64e3', highlight: { background: '#d8baff', border: '#bb86fc' } },
                    font: { color: '#121212' }
                },
                edges: {
                    color: { color: '#888', highlight: '#fff' },
                    smooth: { enabled: true, type: 'dynamic' }
                },
                physics: {
                    enabled: true,
                    solver: 'barnesHut',
                    barnesHut: { gravitationalConstant: -4000, centralGravity: 0.1, springLength: 150 }
                }
            };
            new vis.Network(topologyMapEl, data, options);
        } catch (e) {
            topologyMapEl.innerHTML = '<p style="color: #e57373;">Error rendering topology: ' + e.message + '</p>';
            console.error('Vis.js Error:', e);
        }
    } else {
        topologyMapEl.innerHTML = '<p>No traceroute data available to build topology map.</p>';
    }
});
</script>
EOF
        echo "</body></html>"
    } > "$html_output_file"

    debug_log "New modular dashboard v7 generated at $html_output_file"
}
