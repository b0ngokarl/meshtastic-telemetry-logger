#!/usr/bin/env python3

"""
GPS Map Generator for Meshtastic Telemetry Logger
Extracts GPS coordinates from nodes data and generates interactive map HTML
"""

import csv
import json
import re
from datetime import datetime
from pathlib import Path

def parse_gps_coordinate(coord_str):
    """Parse GPS coordinate from format '50.3480°' to float"""
    if not coord_str or coord_str == 'N/A':
        return None
    
    # Remove the degree symbol and convert to float
    try:
        return float(coord_str.replace('°', ''))
    except (ValueError, AttributeError):
        return None

def extract_gps_nodes(nodes_csv_file='nodes_log.csv'):
    """Extract all nodes with valid GPS coordinates"""
    gps_nodes = []
    
    if not Path(nodes_csv_file).exists():
        print(f"Warning: {nodes_csv_file} not found")
        return gps_nodes
    
    try:
        with open(nodes_csv_file, 'r', encoding='utf-8') as file:
            reader = csv.DictReader(file)
            
            for row in reader:
                lat = parse_gps_coordinate(row.get('Latitude', ''))
                lon = parse_gps_coordinate(row.get('Longitude', ''))
                
                if lat is not None and lon is not None:
                    # Get additional node information
                    node_data = {
                        'id': row.get('ID', 'Unknown'),
                        'name': row.get('User', row.get('AKA', 'Unknown')),
                        'aka': row.get('AKA', ''),
                        'hardware': row.get('Hardware', 'Unknown'),
                        'role': row.get('Role', 'Unknown'),
                        'latitude': lat,
                        'longitude': lon,
                        'altitude': row.get('Altitude', 'N/A'),
                        'battery': row.get('Battery', 'N/A'),
                        'channel_util': row.get('Channel_util', 'N/A'),
                        'tx_air_util': row.get('Tx_air_util', 'N/A'),
                        'snr': row.get('SNR', 'N/A'),
                        'hops': row.get('Hops', 'N/A'),
                        'last_heard': row.get('LastHeard', 'N/A'),
                        'since': row.get('Since', 'N/A')
                    }
                    
                    gps_nodes.append(node_data)
                    
    except Exception as e:
        print(f"Error reading {nodes_csv_file}: {e}")
    
    return gps_nodes

def calculate_map_center(nodes):
    """Calculate the center point of all GPS coordinates"""
    if not nodes:
        # Default to central Germany (approximate center of the network)
        return {'lat': 50.1109, 'lng': 8.6821}
    
    total_lat = sum(node['latitude'] for node in nodes)
    total_lng = sum(node['longitude'] for node in nodes)
    count = len(nodes)
    
    return {
        'lat': total_lat / count,
        'lng': total_lng / count
    }

def generate_map_html(nodes, map_id='gps-map'):
    """Generate HTML for the interactive GPS map"""
    if not nodes:
        return f'<div id="{map_id}" style="height: 400px; background: #f0f0f0; display: flex; align-items: center; justify-content: center; color: #666;">No GPS coordinates available</div>'
    
    center = calculate_map_center(nodes)
    nodes_json = json.dumps(nodes, indent=2)
    
    html = f'''
    <div id="{map_id}" style="height: 500px; width: 100%; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.1);"></div>
    
    <script>
        // Initialize the map
        function initGPSMap() {{
            // Check if Leaflet is available
            if (typeof L === 'undefined') {{
                console.error('Leaflet library not loaded');
                document.getElementById('{map_id}').innerHTML = '<div style="padding: 20px; text-align: center; color: #666;">Map library not available</div>';
                return;
            }}
            
            // Node data
            const nodes = {nodes_json};
            
            // Create map centered on approximate center; we'll adjust later after adding markers
            const map = L.map('{map_id}').setView([{center['lat']}, {center['lng']}], 10);
            
            // Add OpenStreetMap tiles
            L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
                attribution: '© OpenStreetMap contributors',
                maxZoom: 18
            }}).addTo(map);
            
            // Custom icon for Meshtastic nodes
            const nodeIcon = L.divIcon({{
                className: 'custom-node-icon',
                html: '<div style="background: #007acc; border: 2px solid white; border-radius: 50%; width: 12px; height: 12px; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                iconSize: [16, 16],
                iconAnchor: [8, 8]
            }});
            
            const routerIcon = L.divIcon({{
                className: 'custom-router-icon',
                html: '<div style="background: #ff6b35; border: 2px solid white; border-radius: 50%; width: 16px; height: 16px; box-shadow: 0 2px 4px rgba(0,0,0,0.3);"></div>',
                iconSize: [20, 20],
                iconAnchor: [10, 10]
            }});
            
            // Add markers for each node and collect them to compute bounds
            const markers = [];
            nodes.forEach(node => {{
                const icon = node.role === 'ROUTER' ? routerIcon : nodeIcon;
                
                // Create popup content
                let popupContent = `
                    <div style="font-family: monospace; min-width: 200px;">
                        <h4 style="margin: 0 0 8px 0; color: #333;">${{node.name}}</h4>
                        <div style="font-size: 12px; color: #666; margin-bottom: 8px;">
                            <strong>ID:</strong> ${{node.id}}<br>
                            <strong>Hardware:</strong> ${{node.hardware}}<br>
                            ${{node.role !== 'Unknown' ? '<strong>Role:</strong> ' + node.role + '<br>' : ''}}
                        </div>
                        <div style="font-size: 11px; color: #888;">
                            <strong>Coordinates:</strong> ${{node.latitude.toFixed(4)}}, ${{node.longitude.toFixed(4)}}<br>
                            ${{node.altitude !== 'N/A' ? '<strong>Altitude:</strong> ' + node.altitude + '<br>' : ''}}
                            ${{node.battery !== 'N/A' ? '<strong>Battery:</strong> ' + node.battery + '<br>' : ''}}
                            ${{node.snr !== 'N/A' ? '<strong>SNR:</strong> ' + node.snr + '<br>' : ''}}
                            ${{node.hops !== 'N/A' ? '<strong>Hops:</strong> ' + node.hops + '<br>' : ''}}
                            ${{node.last_heard !== 'N/A' ? '<strong>Last Heard:</strong> ' + node.last_heard + '<br>' : ''}}
                        </div>
                    </div>
                `;
                
                const marker = L.marker([node.latitude, node.longitude], {{icon: icon}})
                    .addTo(map)
                    .bindPopup(popupContent);
                markers.push(marker);
            }});
            
            // Fit map to show all markers
            if (markers.length > 1) {{
                const group = L.featureGroup(markers);
                map.fitBounds(group.getBounds().pad(0.1));
            }} else if (markers.length === 1) {{
                map.setView(markers[0].getLatLng(), 13);
            }}

            // Ensure proper rendering if container was hidden/collapsible
            setTimeout(() => map.invalidateSize(), 200);
        }}
        
        // Initialize map when DOM is ready
        if (document.readyState === 'loading') {{
            document.addEventListener('DOMContentLoaded', initGPSMap);
        }} else {{
            initGPSMap();
        }}
    </script>
    '''
    
    return html

def generate_gps_statistics(nodes):
    """Generate statistics about GPS nodes"""
    if not nodes:
        return "No GPS data available"
    
    total_nodes = len(nodes)
    routers = len([n for n in nodes if n['role'] == 'ROUTER'])
    clients = total_nodes - routers
    
    # Calculate geographic bounds
    lats = [n['latitude'] for n in nodes]
    lngs = [n['longitude'] for n in nodes]
    
    bounds = {
        'north': max(lats),
        'south': min(lats),
        'east': max(lngs),
        'west': min(lngs)
    }
    
    # Approximate distance calculation (very rough)
    lat_diff = bounds['north'] - bounds['south']
    lng_diff = bounds['east'] - bounds['west']
    approx_distance_km = max(lat_diff, lng_diff) * 111  # 1 degree ≈ 111 km
    
    return f"""
    <div class="gps-stats" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 0;">
        <div class="stat-card" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px; border-radius: 8px; text-align: center;">
            <div style="font-size: 24px; font-weight: bold;">{total_nodes}</div>
            <div style="font-size: 12px; opacity: 0.9;">Nodes with GPS</div>
        </div>
        <div class="stat-card" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); color: white; padding: 15px; border-radius: 8px; text-align: center;">
            <div style="font-size: 24px; font-weight: bold;">{routers}</div>
            <div style="font-size: 12px; opacity: 0.9;">Routers</div>
        </div>
        <div class="stat-card" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%); color: white; padding: 15px; border-radius: 8px; text-align: center;">
            <div style="font-size: 24px; font-weight: bold;">{clients}</div>
            <div style="font-size: 12px; opacity: 0.9;">Clients</div>
        </div>
        <div class="stat-card" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%); color: white; padding: 15px; border-radius: 8px; text-align: center;">
            <div style="font-size: 24px; font-weight: bold;">{approx_distance_km:.0f} km</div>
            <div style="font-size: 12px; opacity: 0.9;">Network Span</div>
        </div>
    </div>
    """

def generate_gps_map_section(nodes_csv_file='nodes_log.csv'):
    """Generate complete GPS map section for HTML dashboard"""
    nodes = extract_gps_nodes(nodes_csv_file)
    
    if not nodes:
        return '''
        <div class="card">
            <div style="text-align: center; padding: 40px; color: #666;">
                <i class="fas fa-map-marker-alt" style="font-size: 48px; margin-bottom: 20px; opacity: 0.3;"></i>
                <h3>No GPS Data Available</h3>
                <p>No nodes with valid GPS coordinates found in the network.</p>
            </div>
        </div>
        '''
    
    stats_html = generate_gps_statistics(nodes)
    map_html = generate_map_html(nodes)
    
    return f'''
        <div class="card">
            <h3 class="collapsible" onclick="toggleSection('gps-map-section')">
                <i class="fas fa-map-marked-alt"></i> Network GPS Map ({len(nodes)} nodes)
                <i class="fas fa-chevron-down"></i>
            </h3>
            <div id="gps-map-section" class="collapsible-content" style="display: block;">
                {stats_html}
                <div style="margin: 20px 0;">
                    <h4 style="margin-bottom: 10px;"><i class="fas fa-globe"></i> Interactive Network Map</h4>
                    <p style="font-size: 14px; color: #666; margin-bottom: 20px;">
                        Click on markers to view detailed node information. Blue markers represent client nodes, orange markers represent routers.
                    </p>
                    {map_html}
                </div>
                <div style="margin-top: 20px; font-size: 12px; color: #888; text-align: center;">
                    <i class="fas fa-info-circle"></i> Map data © OpenStreetMap contributors | Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                </div>
            </div>
        </div>
        '''

if __name__ == '__main__':
    import sys
    
    nodes_file = sys.argv[1] if len(sys.argv) > 1 else 'nodes_log.csv'
    
    print("=== Meshtastic GPS Map Generator ===")
    print(f"Processing: {nodes_file}")
    
    nodes = extract_gps_nodes(nodes_file)
    print(f"Found {len(nodes)} nodes with GPS coordinates")
    
    if nodes:
        print("\nNodes with GPS:")
        for node in nodes:
            print(f"  {node['id']} ({node['name']}) - {node['latitude']:.4f}, {node['longitude']:.4f}")
    
    # Generate map section
    section_html = generate_gps_map_section(nodes_file)
    
    # Save to file
    with open('gps_map_section.html', 'w') as f:
        f.write(section_html)
    
    print(f"\nGPS map section saved to: gps_map_section.html")