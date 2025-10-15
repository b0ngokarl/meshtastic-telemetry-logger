#!/bin/bash#!/bin/bash



# html_generator.sh - New Modular Dashboard Generator# html_generator_v2.sh - New Modular Dashboard Generator



# Source common utilities# Source common utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common_utils.sh"source "$SCRIPT_DIR/common_utils.sh"



# --- MODULE: NODE DETAILS TABLE ---# --- MODULE: NODE DETAILS TABLE ---

generate_nodes_table() {generate_nodes_table() {

    local nodes_csv_file="${1:-$NODES_CSV}"    local nodes_csv_file="${1:-$NODES_CSV}"

    if [ ! -f "$nodes_csv_file" ]; then    if [ ! -f "$nodes_csv_file" ]; then

        echo "<p>Node data file not found.</p>"        echo "<p>Node data file not found.</p>"

        return        return

    fi    fi



    echo "<div style='overflow-x:auto;'>"    echo "<div style='overflow-x:auto;'>"

    echo "<table>"    echo "<table>"

    echo "<thead><tr><th>Node</th><th>ID</th><th>Role</th><th>Last Heard</th><th>Battery</th><th>Voltage</th><th>Success %</th></tr></thead>"    echo "<thead><tr><th>Node</th><th>ID</th><th>Role</th><th>Last Heard</th><th>Battery</th><th>Voltage</th><th>Success %</th></tr></thead>"

    echo "<tbody>"    echo "<tbody>"

        

    local stats_file    # Read the stats and nodes CSV files

    stats_file=$(compute_telemetry_stats)    local stats_file

        stats_file=$(compute_telemetry_stats)

    local awk_env_vars=()    

    for node_id in "${!NODE_INFO_CACHE[@]}"; do    # Use awk to join nodes_log.csv and the stats output

        local clean_node_id    awk -F, '

        clean_node_id=$(echo "$node_id" | sed 's/!//g')        BEGIN { OFS=","; while((getline < "'"$stats_file"'") > 0) { split($0, a, "|"); stats[a[1]]=a[5] } }

        awk_env_vars+=("NODE_NAME_${clean_node_id}=${NODE_INFO_CACHE[$node_id]}")        NR > 1 {

    done            id = $2

            gsub(/"/, "", id)

    env "${awk_env_vars[@]}" awk -F, '            

        BEGIN {             # Get friendly name from cache via environment

            OFS=",";             friendly_name = ENVIRON["NODE_NAME_" id]

            while((getline < "'"$stats_file"'") > 0) {             if (friendly_name == "") friendly_name = $1

                split($0, a, "|");            if (friendly_name == "") friendly_name = id

                clean_id = a[1];

                gsub(/!/, "", clean_id);            role = $5

                stats[clean_id] = a[5];             last_heard = $11

                voltages[clean_id] = a[9];            battery = $9

            }             voltage = "N/A" # Not in this CSV, would need another join or be added

        }            

        NR > 1 {            # Get success rate from stats array

            id_raw = $2;            rate = stats[id]

            gsub(/"/, "", id_raw);            if (rate == "") rate = 0

            id_clean = id_raw;

            gsub(/!/, "", id_clean);            # Determine color class for success rate

                        rate_class = "success-rate-low"

            friendly_name = ENVIRON["NODE_NAME_" id_clean];            if (rate > 90) rate_class = "success-rate-good"

            if (friendly_name == "") friendly_name = $1;            else if (rate > 70) rate_class = "success-rate-medium"

            gsub(/"/, "", friendly_name);

            if (friendly_name == "") friendly_name = id_raw;            # Format battery level

            if (battery ~ /^[0-9]+$/) {

            role = $5;                battery_display = battery "%"

            last_heard = $11;            } else {

            battery = $9;                battery_display = "N/A"

                        }

            voltage = voltages[id_clean];

            if (voltage == "" || voltage == "N/A") voltage = "N/A";            printf "<tr>"

            printf "<td>%s</td>", friendly_name

            rate = stats[id_clean];            printf "<td>%s</td>", id

            if (rate == "") rate = 0;            printf "<td>%s</td>", role

            printf "<td>%s</td>", last_heard

            rate_class = "success-rate-low";            printf "<td>%s</td>", battery_display

            if (rate > 90) rate_class = "success-rate-good";            printf "<td>%sV</td>", voltage

            else if (rate > 70) rate_class = "success-rate-medium";            printf "<td><span class=\"%s\">%.1f%%</span></td>", rate_class, rate

            printf "</tr>\n"

            battery_display = (battery ~ /^[0-9]+(\.[0-9]+)?$/) ? battery "%" : "N/A";        }

            voltage_display = (voltage != "N/A") ? voltage "V" : "N/A";    ' "$nodes_csv_file"



            printf "<tr>";    echo "</tbody></table>"

            printf "<td>%s</td>", friendly_name;    echo "</div>"

            printf "<td>%s</td>", id_raw;    

            printf "<td>%s</td>", role;    rm -f "$stats_file"

            printf "<td>%s</td>", last_heard;}

            printf "<td>%s</td>", battery_display;

            printf "<td>%s</td>", voltage_display;

            printf "<td><span class=\"%s\">%.1f%%</span></td>", rate_class, rate;# --- MAIN DASHBOARD GENERATOR ---

            printf "</tr>\n";generate_dashboard_optimized() {

        }    local html_output_file="${HTML_OUTPUT:-"stats.html"}"

    ' "$nodes_csv_file"    debug_log "Starting new modular dashboard generation v2 (Output: $html_output_file)"



    echo "</tbody></table>"    # Prepare node names for the awk script by exporting them

    echo "</div>"    for node_id in "${!NODE_INFO_CACHE[@]}"; do

            export "NODE_NAME_${node_id}=${NODE_INFO_CACHE[$node_id]}"

    rm -f "$stats_file"    done

}

    # Generate modular components

    local nodes_table_html

# --- MAIN DASHBOARD GENERATOR ---    nodes_table_html=$(generate_nodes_table)

generate_dashboard_optimized() {

    local html_output_file="${HTML_OUTPUT:-"stats.html"}"    # --- HTML Structure ---

    debug_log "Starting new modular dashboard generation (Output: $html_output_file)"    {

        echo "<!DOCTYPE html><html lang='en'><head>"

    local nodes_table_html        echo "<meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'>"

    nodes_table_html=$(generate_nodes_table)        echo "<meta http-equiv='refresh' content='${POLLING_INTERVAL:-300}'>"

            echo "<title>Meshtastic Network Dashboard</title>"

    local traceroute_data=""        echo "<script type='text/javascript' src='https://unpkg.com/vis-network/standalone/umd/vis-network.min.js'></script>"

    if [ -f "$ROUTING_LOG_RAW" ]; then        echo "<style>"

        traceroute_data=$(tail -n +2 "$ROUTING_LOG_RAW" | sed 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g')        echo "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background-color:#121212;color:#e0e0e0;margin:0;padding:20px}"

    fi        echo ".container{max-width:95%;margin:auto}h1,h2{color:#bb86fc;border-bottom:2px solid #373737;padding-bottom:10px}"

        echo ".grid-container{display:grid;grid-template-columns:repeat(auto-fit,minmax(450px,1fr));gap:20px}"

    {        echo ".section{background-color:#1e1e1e;padding:20px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.4);transition:transform .2s}.section:hover{transform:translateY(-5px)}"

        echo "<!DOCTYPE html><html lang='en'><head>"        echo ".chart-container{text-align:center;margin:20px 0}img.chart{max-width:100%;height:auto;border-radius:8px;background-color:white}"

        echo "<meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'>"        echo "#last-updated{text-align:center;color:#a0a0a0;margin-bottom:20px;font-size:.9em}"

        echo "<meta http-equiv='refresh' content='${POLLING_INTERVAL:-300}'>"        echo "#topology-map{width:100%;height:500px;border:1px solid #373737;border-radius:8px;background-color:#2c2c2c}"

        echo "<title>Meshtastic Network Dashboard</title>"        echo "table{width:100%;border-collapse:collapse;margin-top:15px}th,td{padding:12px;text-align:left;border-bottom:1px solid #373737}th{background-color:#333;color:#bb86fc}tr:nth-child(even){background-color:#2c2c2c}"

        echo "<script type='text/javascript' src='https://unpkg.com/vis-network/standalone/umd/vis-network.min.js'></script>"        echo ".success-rate-good{color:#81c784;font-weight:bold}.success-rate-medium{color:#ffb74d;font-weight:bold}.success-rate-low{color:#e57373;font-weight:bold}"

        echo "<style>"        echo "</style></head><body><div class='container'>"

        echo "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;background-color:#121212;color:#e0e0e0;margin:0;padding:20px}"        echo "<h1>Meshtastic Network Dashboard</h1><div id='last-updated'>Last Updated: $(date)</div>"

        echo ".container{max-width:95%;margin:auto}h1,h2{color:#bb86fc;border-bottom:2px solid #373737;padding-bottom:10px}"        echo "<div class='grid-container'>"

        echo ".grid-container{display:grid;grid-template-columns:repeat(auto-fit,minmax(450px,1fr));gap:20px}"        

        echo ".section{background-color:#1e1e1e;padding:20px;border-radius:12px;box-shadow:0 4px 12px rgba(0,0,0,0.4);transition:transform .2s}.section:hover{transform:translateY(-5px)}"        echo "<div class='section' id='status-section'><h2>Network Status</h2><div id='network-news-container'><p>Loading network news...</p></div></div>"

        echo ".chart-container{text-align:center;margin:20px 0}img.chart{max-width:100%;height:auto;border-radius:8px;background-color:white}"        echo "<div class='section' id='comprehensive-chart-section'><h2>Comprehensive Telemetry</h2><div class='chart-container' id='comprehensive-chart-container'><p>Loading chart...</p></div></div>"

        echo "#last-updated{text-align:center;color:#a0a0a0;margin-bottom:20px;font-size:.9em}"        echo "<div class='section' id='utilization-chart-section'><h2>Network Utilization</h2><div class='chart-container' id='utilization-chart-container'><p>Loading chart...</p></div></div>"

        echo "#topology-map{width:100%;height:500px;border:1px solid #373737;border-radius:8px;background-color:#2c2c2c}"        

        echo "table{width:100%;border-collapse:collapse;margin-top:15px}th,td{padding:12px;text-align:left;border-bottom:1px solid #373737}th{background-color:#333;color:#bb86fc}tr:nth-child(even){background-color:#2c2c2c}"        echo "<div class='section' id='nodes-section'><h2>Node Details</h2><div id='nodes-table-container'>$nodes_table_html</div></div>"

        echo ".success-rate-good{color:#81c784;font-weight:bold}.success-rate-medium{color:#ffb74d;font-weight:bold}.success-rate-low{color:#e57373;font-weight:bold}"        

        echo "</style></head><body><div class='container'>"        echo "</div>" # End grid-container

        echo "<h1>Meshtastic Network Dashboard</h1><div id='last-updated'>Last Updated: $(date)</div>"        

        echo "<div class='grid-container'>"        echo "<div class='section' id='topology-section'><h2>Network Topology</h2><div id='topology-map'></div><div id='traceroute-data-container' style='display:none;'></div></div>"

                

        echo "<div class='section' id='status-section'><h2>Network Status</h2><div id='network-news-container'><p>Loading network news...</p></div></div>"        echo "</div>" # End container

        echo "<div class='section' id='comprehensive-chart-section'><h2>Comprehensive Telemetry</h2><div class='chart-container' id='comprehensive-chart-container'><p>Loading chart...</p></div></div>"        

        echo "<div class='section' id='utilization-chart-section'><h2>Network Utilization</h2><div class='chart-container' id='utilization-chart-container'><p>Loading chart...</p></div></div>"        # --- JavaScript for dynamic content ---

                cat <<'EOF'

        echo "<div class='section' id='nodes-section'><h2>Node Details</h2><div id='nodes-table-container'>$nodes_table_html</div></div>"<script>

        document.addEventListener('DOMContentLoaded', function() {

        echo "</div>"    console.log('Dashboard v2 loaded. Initializing dynamic content...');

            

        echo "<div class='section' id='topology-section'><h2>Network Topology</h2><div id='topology-map'></div><div id='traceroute-data-container' style='display:none;'>$traceroute_data</div></div>"    const tracerouteDataEl = document.getElementById('traceroute-data-container');

            const topologyMapEl = document.getElementById('topology-map');

        echo "</div>"

            if (tracerouteDataEl && topologyMapEl && tracerouteDataEl.innerHTML.trim() !== '') {

        cat <<'EOF'        try {

<script>            const rawData = tracerouteDataEl.textContent;

document.addEventListener('DOMContentLoaded', function() {            const lines = rawData.split('\n').filter(line => line.trim() !== '');

    const tracerouteDataEl = document.getElementById('traceroute-data-container');            

    const topologyMapEl = document.getElementById('topology-map');            const nodes = new vis.DataSet();

            const edges = new vis.DataSet();

    if (tracerouteDataEl && topologyMapEl && tracerouteDataEl.innerHTML.trim() !== '') {            const nodeIds = new Set();

        try {

            const rawData = tracerouteDataEl.textContent;            lines.forEach(line => {

            const lines = rawData.split('\n').filter(line => line.trim() !== '');                const parts = line.split(',');

                            if (parts.length < 3) return;

            const nodes = new vis.DataSet();

            const edges = new vis.DataSet();                const fromNode = parts[1].trim();

            const nodeIds = new Set();                const toNode = parts[2].trim();

                const routePath = parts[3] ? parts[3].split(' -> ') : [];

            lines.forEach(line => {

                const parts = line.split(',');                // Add the main 'from' and 'to' nodes

                if (parts.length < 4) return;                [fromNode, toNode].forEach(nodeId => {

                    if (!nodeIds.has(nodeId)) {

                const fromNode = parts[1].trim();                        nodes.add({ id: nodeId, label: nodeId });

                const toNode = parts[2].trim();                        nodeIds.add(nodeId);

                                    }

                const routePathStr = parts[3].replace(/"/g, '');                });

                const routePath = routePathStr.split(' -> ');

                // Create edges from the route path

                [fromNode, toNode, ...routePath].forEach(nodeId => {                if (routePath.length > 1) {

                    if (nodeId && !nodeIds.has(nodeId)) {                    for (let i = 0; i < routePath.length - 1; i++) {

                        nodes.add({ id: nodeId, label: nodeId });                        const source = routePath[i].trim();

                        nodeIds.add(nodeId);                        const target = routePath[i+1].trim();

                    }                        const edgeId = `${source}-${target}`;

                });                        if (!edges.get(edgeId) && !edges.get(`${target}-${source}`)) {

                            edges.add({ id: edgeId, from: source, to: target, arrows: 'to' });

                if (routePath.length > 1) {                        }

                    for (let i = 0; i < routePath.length - 1; i++) {                    }

                        const source = routePath[i].trim();                }

                        const target = routePath[i+1].trim();            });

                        if (source && target) {

                            const edgeId1 = `${source}-${target}`;            const data = { nodes: nodes, edges: edges };

                            const edgeId2 = `${target}-${source}`;            const options = {

                            if (!edges.get(edgeId1) && !edges.get(edgeId2)) {                layout: {

                                edges.add({ id: edgeId1, from: source, to: target, arrows: 'to' });                    hierarchical: false,

                            }                    improvedLayout: true

                        }                },

                    }                nodes: {

                } else if (fromNode && toNode && fromNode !== toNode) {                    shape: 'box',

                    const edgeId1 = `${fromNode}-${toNode}`;                    color: {

                    const edgeId2 = `${toNode}-${fromNode}`;                        background: '#bb86fc',

                    if (!edges.get(edgeId1) && !edges.get(edgeId2)) {                        border: '#9e64e3',

                        edges.add({ id: edgeId1, from: fromNode, to: toNode, arrows: 'to', dashes: true });                        highlight: { background: '#d8baff', border: '#bb86fc' }

                    }                    },

                }                    font: { color: '#121212' }

            });                },

                edges: {

            const data = { nodes: nodes, edges: edges };                    color: {

            const options = {                        color: '#888',

                layout: { improvedLayout: true },                        highlight: '#fff'

                nodes: {                    }

                    shape: 'box',                },

                    color: { background: '#bb86fc', border: '#9e64e3' },                physics: {

                    font: { color: '#121212' }                    enabled: true,

                },                    solver: 'barnesHut',

                edges: {                    barnesHut: {

                    color: { color: '#888', highlight: '#fff' },                        gravitationalConstant: -3000,

                    smooth: { enabled: true, type: 'cubicBezier', forceDirection: 'horizontal', roundness: 0.4 }                        springConstant: 0.04,

                },                        springLength: 120

                physics: {                    }

                    enabled: true,                }

                    solver: 'barnesHut',            };

                    barnesHut: { gravitationalConstant: -4000, centralGravity: 0.1, springLength: 150 }            new vis.Network(topologyMapEl, data, options);

                }        } catch (e) {

            };            topologyMapEl.innerHTML = '<p style="color: #e57373;">Error rendering network topology: ' + e.message + '</p>';

            new vis.Network(topologyMapEl, data, options);            console.error('Vis.js Error:', e);

        } catch (e) {        }

            topologyMapEl.innerHTML = '<p style="color: #e57373;">Error: ' + e.message + '</p>';    } else {

        }        topologyMapEl.innerHTML = '<p>No traceroute data available to build topology map.</p>';

    } else {    }

        topologyMapEl.innerHTML = '<p>No traceroute data available.</p>';});

    }</script>

});EOF

</script>        

EOF        echo "</body></html>"

            } > "$html_output_file"

        echo "</body></html>"

    } > "$html_output_file"    debug_log "New modular dashboard v2 generated at $html_output_file"

}

    debug_log "New modular dashboard generated at $html_output_file"
}
