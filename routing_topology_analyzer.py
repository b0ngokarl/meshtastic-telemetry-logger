#!/usr/bin/env python3
"""
Routing Topology Analyzer for Meshtastic Telemetry Logger
Analyzes routing data and generates beautiful network topology visualizations.
"""

import csv
import json
import os
from datetime import datetime, timedelta
from typing import Dict, List, Set, Tuple, Optional

def load_routing_data(routing_csv='routing_log.csv', relationships_csv='node_relationships.csv'):
    """Load routing and relationship data from CSV files"""
    routes = []
    relationships = []
    
    # Load routing data
    if os.path.exists(routing_csv):
        with open(routing_csv, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                routes.append(row)
    
    # Load relationship data 
    if os.path.exists(relationships_csv):
        with open(relationships_csv, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                relationships.append(row)
    
    return routes, relationships

def get_node_names(nodes_csv='nodes_log.csv'):
    """Get mapping of node IDs to friendly names"""
    node_names = {}
    
    if os.path.exists(nodes_csv):
        with open(nodes_csv, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                node_id = row.get('ID', '').strip()
                user = row.get('User', '').strip()
                aka = row.get('AKA', '').strip()
                
                if node_id:
                    # Use AKA if available, otherwise use User, otherwise use ID
                    friendly_name = aka if aka and aka != 'N/A' else (user if user and user != 'N/A' else node_id)
                    node_names[node_id] = friendly_name
    
    # Also load any nodes from network_state.json for complete name mapping
    state_file = 'network_state.json'
    if os.path.exists(state_file):
        try:
            with open(state_file, 'r') as sf:
                state_data = json.load(sf)
            for node_id, info in state_data.items():
                # Skip if already have a mapping
                if node_id in node_names:
                    continue
                # Use AKA if present and not N/A, else user, else node_id
                aka = info.get('aka', '').strip()
                user = info.get('user', '').strip()
                friendly = aka if aka and aka.upper() != 'N/A' else (user if user and user.upper() != 'N/A' else node_id)
                node_names[node_id] = friendly
        except Exception:
            pass
    # Fallback: query Meshtastic CLI for any additional nodes
    try:
        import subprocess
        cli_output = subprocess.check_output(["meshtastic", "--nodes", "--json"], text=True)
        cli_data = json.loads(cli_output)
        for node in cli_data.get('nodes', []):
            nid = node.get('id') or node.get('_id') or ''
            if nid and nid not in node_names:
                # Use AKA or user-friendly name from CLI
                friendly = node.get('user') or node.get('aka') or nid
                node_names[nid] = friendly
    except Exception:
        pass
    return node_names

def analyze_current_routes(routes, time_window_hours=24):
    """Analyze current routes within the specified time window"""
    cutoff_time = datetime.now()
    
    # Group routes by destination
    routes_by_dest = {}
    route_changes = {}
    
    # Filter out traceroutes to invalid node '!ab123456'
    routes = [r for r in routes if r.get('destination') not in ('!ab123456', 'ab123456')]
    for route in routes:
        try:
            # Parse timestamp more flexibly
            timestamp_str = route['timestamp']
            if timestamp_str.endswith('Z'):
                timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                # Convert to local time for comparison
                timestamp = timestamp.replace(tzinfo=None)
            elif '+' in timestamp_str:
                # Remove timezone info for naive comparison
                timestamp = datetime.fromisoformat(timestamp_str.split('+')[0])
            else:
                timestamp = datetime.fromisoformat(timestamp_str)
            
            # Check if within time window
            time_diff = (cutoff_time - timestamp).total_seconds() / 3600
            if time_diff > time_window_hours:
                continue
                
            dest = route['destination']
            direction = route['direction']
            
            if dest not in routes_by_dest:
                routes_by_dest[dest] = {'forward': [], 'return': []}
                
            routes_by_dest[dest][direction].append({
                'timestamp': timestamp,
                'route_hops': route['route_hops'],
                'signal_strengths': route['signal_strengths'],
                'hop_count': int(route['hop_count']) if route['hop_count'] else 0,
                'success': route['success'] == 'true'
            })
        except (ValueError, KeyError) as e:
            continue
    
    # Sort routes by timestamp and detect changes
    for dest in routes_by_dest:
        for direction in ['forward', 'return']:
            routes_by_dest[dest][direction].sort(key=lambda x: x['timestamp'])
            
            # Detect route changes
            if len(routes_by_dest[dest][direction]) > 1:
                current_route = routes_by_dest[dest][direction][-1]['route_hops']
                previous_routes = [r['route_hops'] for r in routes_by_dest[dest][direction][:-1]]
                
                # Check if current route differs from any previous route
                if current_route not in previous_routes:
                    if dest not in route_changes:
                        route_changes[dest] = {}
                    route_changes[dest][direction] = {
                        'current': current_route,
                        'previous': previous_routes[-1] if previous_routes else None,
                        'changed_at': routes_by_dest[dest][direction][-1]['timestamp']
                    }
    
    return routes_by_dest, route_changes

def generate_topology_html(routes_by_dest, route_changes, node_names):
    """Generate HTML for network topology visualization"""
    
    html = """
<div style='background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #007bff;'>
<h3 id='network-topology' style='margin-top: 0; color: #007bff;'>🗺️ Network Routing Topology</h3>
<div class='topology-content'>
"""
    
    if not routes_by_dest:
        html += "<p><em>No routing data available yet. Traceroutes will appear here after collection.</em></p>"
        html += "</div></div>"
        return html
    
    # Summary statistics
    total_destinations = len(routes_by_dest)
    successful_routes = sum(1 for dest in routes_by_dest if any(
        route['success'] for route in routes_by_dest[dest]['forward'] + routes_by_dest[dest]['return']
    ))
    asymmetric_routes = sum(1 for dest in routes_by_dest if dest in route_changes and 
                          ('forward' in route_changes[dest] or 'return' in route_changes[dest]))
    
    html += f"""
<div class='topology-summary' style='background: #e9ecef; padding: 10px; border-radius: 5px; margin-bottom: 15px;'>
<p><strong>Network Status:</strong> {successful_routes}/{total_destinations} destinations reachable | 
<span style='color: #ffc107;'>Route changes: {len(route_changes)}</span> | 
<span style='color: #dc3545;'>Asymmetric: {asymmetric_routes}</span></p>
</div>
"""
    
    # Generate route visualizations
    for dest in sorted(routes_by_dest.keys()):
        dest_data = routes_by_dest[dest]
        # Use friendly name or strip '!' for fallback
        dest_name = node_names.get(dest, dest.lstrip('!'))
        
        # Get current routes
        current_forward = dest_data['forward'][-1] if dest_data['forward'] else None
        current_return = dest_data['return'][-1] if dest_data['return'] else None
        
        # Determine route status
        if current_forward and current_return:
            if current_forward['route_hops'] == current_return['route_hops'].replace('→', '←'):
                status_icon = "✅"
                status_text = "Symmetric route"
                status_color = "#28a745"
            else:
                status_icon = "⚠️"
                status_text = "Asymmetric route"
                status_color = "#ffc107"
        elif current_forward or current_return:
            status_icon = "🔶"
            status_text = "Partial route"
            status_color = "#fd7e14"
        else:
            status_icon = "❌"
            status_text = "Route failed"
            status_color = "#dc3545"
        
        html += f"""
<div style='border: 1px solid #dee2e6; border-radius: 5px; padding: 15px; margin: 10px 0; background: white;'>
<h4 style='margin-top: 0; color: {status_color};'>📡 To: {dest_name} ({dest})</h4>
"""
        
        # Forward route with friendly names
        if current_forward and current_forward['success']:
            hops = [h.strip() for h in current_forward['route_hops'].split('→')]
            # Map to friendly names or use ID without '!'
            named = [node_names.get(h, h.lstrip('!')) for h in hops]
            route_display = ' ──→ '.join(named)
            signal_info = f" ({current_forward['signal_strengths']})" if current_forward['signal_strengths'] else ""
            html += f"<p><strong>Forward:</strong> {route_display}{signal_info}</p>"
        else:
            html += "<p><strong>Forward:</strong> <span style='color: #dc3545;'>Route failed or unavailable</span></p>"
        
        # Return route with friendly names
        if current_return and current_return['success']:
            hops_r = [h.strip() for h in current_return['route_hops'].split('→')]
            # Map to friendly names or use ID without '!'
            named_r = [node_names.get(h, h.lstrip('!')) for h in hops_r]
            route_display = ' ──→ '.join(named_r)
            signal_info = f" ({current_return['signal_strengths']})" if current_return['signal_strengths'] else ""
            html += f"<p><strong>Return:</strong> {route_display}{signal_info}</p>"
        else:
            html += "<p><strong>Return:</strong> <span style='color: #dc3545;'>Route failed or unavailable</span></p>"
        
        # Status and hop count
        hop_count = current_forward['hop_count'] if current_forward else (current_return['hop_count'] if current_return else 0)
        html += f"<p><strong>Status:</strong> {status_icon} {status_text} ({hop_count} hops)</p>"
        
        # Show route changes if any
        if dest in route_changes:
            html += "<div style='background: #fff3cd; padding: 8px; border-radius: 3px; margin-top: 10px; border-left: 3px solid #ffc107;'>"
            html += "<p style='margin: 0; font-size: 0.9em;'><strong>Recent Changes:</strong></p>"
            
            for direction in ['forward', 'return']:
                if direction in route_changes[dest]:
                    change = route_changes[dest][direction]
                    prev_display = change['previous'].replace('→', ' ──→ ') if change['previous'] else 'Unknown'
                    change_time = change['changed_at'].strftime('%m/%d %H:%M')
                    html += f"<p style='margin: 2px 0; font-size: 0.8em; color: #856404;'>"
                    html += f"• {direction.title()}: Was {prev_display} (changed {change_time})</p>"
            
            html += "</div>"
        
        html += "</div>"
    
    html += """
</div>
</div>
"""
    
    return html

def generate_routing_topology_section():
    """Main function to generate the routing topology HTML section"""
    try:
        # Load data
        routes, relationships = load_routing_data()
        # Exclude traceroutes involving the invalid node '!ab123456'
        bad = {'!ab123456', 'ab123456'}
        routes = [r for r in routes if r.get('destination') not in bad and r.get('source') not in bad]
        node_names = get_node_names()

        # Analyze current routes
        routes_by_dest, route_changes = analyze_current_routes(routes)

        # Generate HTML
        html = generate_topology_html(routes_by_dest, route_changes, node_names)
        return html

    except Exception as e:
        return f"""
<div style='background: #f8d7da; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #dc3545;'>
<h3 style='margin-top: 0; color: #dc3545;'>🗺️ Network Routing Topology</h3>
<p><em>Error generating topology visualization: {str(e)}</em></p>
</div>
"""

if __name__ == "__main__":
    # Generate and save the topology section
    html_content = generate_routing_topology_section()
    
    with open('network_topology.html', 'w') as f:
        f.write(html_content)
    
    print("Network topology visualization generated: network_topology.html")