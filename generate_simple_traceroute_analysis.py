#!/usr/bin/env python3

"""
Simplified Network Traceroute Analysis (No External Dependencies)
Generates basic network topology analysis from traceroute data using only standard library
"""

import json
import csv
import os
import sys
from datetime import datetime, timedelta
from collections import defaultdict, Counter

class SimpleTracerouteAnalyzer:
    """Basic network topology analyzer without external dependencies"""
    
    def __init__(self, traceroute_csv="traceroute_log.csv", nodes_csv="nodes_log.csv"):
        self.traceroute_csv = traceroute_csv
        self.nodes_csv = nodes_csv
        self.node_names = {}
        self.routes = []
        self.connections = defaultdict(set)
        self.route_counts = defaultdict(int)
        
        # Load data
        self.load_node_names()
        self.load_traceroute_data()
    
    def load_node_names(self):
        """Load node names from nodes CSV for better labeling"""
        try:
            if os.path.exists(self.nodes_csv):
                with open(self.nodes_csv, 'r') as f:
                    reader = csv.DictReader(f)
                    for row in reader:
                        node_id = row.get('ID', '')
                        user = row.get('User', '')
                        aka = row.get('AKA', '')
                        
                        # Create a nice display name
                        if user and aka:
                            display_name = f"{user} ({aka})"
                        elif user:
                            display_name = user
                        elif aka:
                            display_name = aka
                        else:
                            display_name = node_id
                        
                        self.node_names[node_id] = display_name
                        
                print(f"Loaded {len(self.node_names)} node names")
            else:
                print(f"Node CSV file not found: {self.nodes_csv}")
        except Exception as e:
            print(f"Error loading node names: {e}")
    
    def load_traceroute_data(self, hours=24):
        """Load recent traceroute data and analyze network connections"""
        try:
            if not os.path.exists(self.traceroute_csv):
                print(f"Traceroute CSV file not found: {self.traceroute_csv}")
                return
            
            cutoff_time = datetime.now() - timedelta(hours=hours)
            
            with open(self.traceroute_csv, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    try:
                        timestamp_str = row['timestamp']
                        # Handle various timestamp formats
                        if '+' in timestamp_str:
                            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        else:
                            timestamp = datetime.fromisoformat(timestamp_str)
                        
                        if timestamp >= cutoff_time and row['success'] == 'true' and row['hops'] not in ['NO_ROUTE', 'TIMEOUT', 'ERROR']:
                            self.analyze_route(row['target'], row['hops'])
                            self.routes.append(row)
                    except Exception as e:
                        print(f"Error parsing row: {row}, error: {e}")
                        continue
            
            print(f"Analyzed {len(self.routes)} successful routes")
            
        except Exception as e:
            print(f"Error loading traceroute data: {e}")
    
    def analyze_route(self, target, hops_str):
        """Analyze a route path and build connection graph"""
        if not hops_str or hops_str in ['NO_ROUTE', 'TIMEOUT', 'ERROR', 'PARSE_ERROR']:
            return
        
        # Parse hops (comma-separated node IDs)
        hops = [hop.strip() for hop in hops_str.split(',') if hop.strip()]
        
        if not hops:
            return
        
        # Record connections between consecutive hops
        for i in range(len(hops) - 1):
            from_node = hops[i]
            to_node = hops[i + 1]
            
            self.connections[from_node].add(to_node)
            route_key = f"{from_node}->{to_node}"
            self.route_counts[route_key] += 1
    
    def get_node_label(self, node_id):
        """Get a display label for a node"""
        if node_id in self.node_names:
            return self.node_names[node_id]
        else:
            return node_id[-4:] if len(node_id) > 4 else node_id
    
    def generate_text_topology(self, output_file="network_topology.txt"):
        """Generate text-based network topology visualization"""
        try:
            with open(output_file, 'w') as f:
                f.write("MESHTASTIC NETWORK TOPOLOGY\n")
                f.write("=" * 50 + "\n")
                f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
                
                # Network statistics
                all_nodes = set()
                for node in self.connections:
                    all_nodes.add(node)
                    all_nodes.update(self.connections[node])
                
                total_connections = sum(len(connections) for connections in self.connections.values())
                
                f.write("NETWORK STATISTICS:\n")
                f.write(f"  Total Nodes: {len(all_nodes)}\n")
                f.write(f"  Total Connections: {total_connections}\n")
                f.write(f"  Routes Analyzed: {len(self.routes)}\n\n")
                
                # Node analysis
                f.write("NODE ANALYSIS:\n")
                f.write("-" * 30 + "\n")
                
                node_degrees = {}
                for node in all_nodes:
                    outgoing = len(self.connections.get(node, set()))
                    incoming = sum(1 for connections in self.connections.values() if node in connections)
                    total_degree = outgoing + incoming
                    node_degrees[node] = {'out': outgoing, 'in': incoming, 'total': total_degree}
                
                # Sort nodes by total degree (most connected first)
                sorted_nodes = sorted(node_degrees.items(), key=lambda x: x[1]['total'], reverse=True)
                
                for node, degrees in sorted_nodes:
                    node_label = self.get_node_label(node)
                    role = "HUB" if degrees['total'] > 2 else "RELAY" if degrees['total'] > 1 else "END"
                    f.write(f"  {node_label:20} ({node}) - {role}\n")
                    f.write(f"    Connections: {degrees['total']} (Out: {degrees['out']}, In: {degrees['in']})\n")
                    
                    if node in self.connections:
                        connections_str = ", ".join([self.get_node_label(conn) for conn in self.connections[node]])
                        f.write(f"    Routes to: {connections_str}\n")
                    f.write("\n")
                
                # Route usage analysis
                f.write("ROUTE USAGE ANALYSIS:\n")
                f.write("-" * 30 + "\n")
                
                sorted_routes = sorted(self.route_counts.items(), key=lambda x: x[1], reverse=True)
                for route, count in sorted_routes:
                    from_node, to_node = route.split('->')
                    from_label = self.get_node_label(from_node)
                    to_label = self.get_node_label(to_node)
                    f.write(f"  {from_label} → {to_label}: {count} times\n")
                
                f.write(f"\nTopology saved to: {output_file}\n")
                
            print(f"Text topology saved to: {output_file}")
            return True
            
        except Exception as e:
            print(f"Error generating text topology: {e}")
            return False
    
    def generate_statistics_json(self, output_file="network_topology_stats.json"):
        """Generate network statistics in JSON format"""
        try:
            # Calculate network metrics
            all_nodes = set()
            for node in self.connections:
                all_nodes.add(node)
                all_nodes.update(self.connections[node])
            
            node_degrees = {}
            for node in all_nodes:
                outgoing = len(self.connections.get(node, set()))
                incoming = sum(1 for connections in self.connections.values() if node in connections)
                total_degree = outgoing + incoming
                node_degrees[node] = {
                    'display_name': self.get_node_label(node),
                    'outgoing_connections': outgoing,
                    'incoming_connections': incoming,
                    'total_connections': total_degree,
                    'is_hub': total_degree > 2,
                    'is_endpoint': total_degree == 1
                }
            
            # Find most connected nodes
            sorted_nodes = sorted(node_degrees.items(), key=lambda x: x[1]['total_connections'], reverse=True)
            hub_nodes = [node for node, data in sorted_nodes if data['is_hub']]
            
            stats = {
                'timestamp': datetime.now().isoformat(),
                'network_stats': {
                    'total_nodes': len(all_nodes),
                    'total_routes': sum(len(connections) for connections in self.connections.values()),
                    'analyzed_routes': len(self.routes),
                    'avg_connections': sum(data['total_connections'] for data in node_degrees.values()) / len(all_nodes) if all_nodes else 0
                },
                'node_stats': node_degrees,
                'route_usage': dict(self.route_counts),
                'topology_analysis': {
                    'hub_nodes': hub_nodes,
                    'most_connected': sorted_nodes[0][0] if sorted_nodes else None,
                    'max_connections': sorted_nodes[0][1]['total_connections'] if sorted_nodes else 0,
                    'network_depth': self.calculate_network_depth()
                }
            }
            
            with open(output_file, 'w') as f:
                json.dump(stats, f, indent=2, default=str)
            
            print(f"Statistics saved to: {output_file}")
            return stats
            
        except Exception as e:
            print(f"Error generating statistics: {e}")
            return {}
    
    def calculate_network_depth(self):
        """Calculate the maximum depth of the network (longest path)"""
        try:
            # Simple BFS to find maximum depth from any starting node
            max_depth = 0
            
            for start_node in self.connections:
                visited = set()
                queue = [(start_node, 0)]
                local_max = 0
                
                while queue:
                    node, depth = queue.pop(0)
                    if node in visited:
                        continue
                    
                    visited.add(node)
                    local_max = max(local_max, depth)
                    
                    for neighbor in self.connections.get(node, set()):
                        if neighbor not in visited:
                            queue.append((neighbor, depth + 1))
                
                max_depth = max(max_depth, local_max)
            
            return max_depth
            
        except:
            return 0
    
    def generate_simple_svg(self, output_file="network_topology.svg"):
        """Generate a simple SVG network diagram using only standard library"""
        try:
            # Get all nodes and position them in a simple layout
            all_nodes = set()
            for node in self.connections:
                all_nodes.add(node)
                all_nodes.update(self.connections[node])
            
            if not all_nodes:
                print("No network data to visualize")
                return False
            
            # Calculate simple circular layout
            import math
            node_positions = {}
            node_list = list(all_nodes)
            n_nodes = len(node_list)
            
            center_x, center_y = 300, 300
            radius = 200
            
            for i, node in enumerate(node_list):
                angle = 2 * math.pi * i / n_nodes
                x = center_x + radius * math.cos(angle)
                y = center_y + radius * math.sin(angle)
                node_positions[node] = (x, y)
            
            # Generate SVG
            svg_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="600" height="600" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <style>
      .node {{ fill: #4ECDC4; stroke: #2c3e50; stroke-width: 2; }}
      .hub-node {{ fill: #FF6B6B; }}
      .edge {{ stroke: #666; stroke-width: 2; opacity: 0.7; }}
      .node-label {{ font-family: Arial, sans-serif; font-size: 10px; text-anchor: middle; }}
    </style>
  </defs>
  
  <title>Meshtastic Network Topology</title>
  
  <!-- Background -->
  <rect width="600" height="600" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="300" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="18" font-weight="bold">
    Meshtastic Network Topology
  </text>
  
  <!-- Edges -->
'''
            
            # Draw connections
            for from_node in self.connections:
                from_x, from_y = node_positions[from_node]
                for to_node in self.connections[from_node]:
                    if to_node in node_positions:
                        to_x, to_y = node_positions[to_node]
                        svg_content += f'  <line x1="{from_x}" y1="{from_y}" x2="{to_x}" y2="{to_y}" class="edge"/>\n'
            
            svg_content += '\n  <!-- Nodes -->\n'
            
            # Draw nodes
            for node in all_nodes:
                x, y = node_positions[node]
                
                # Determine node type
                outgoing = len(self.connections.get(node, set()))
                incoming = sum(1 for connections in self.connections.values() if node in connections)
                total_degree = outgoing + incoming
                
                node_class = "hub-node" if total_degree > 2 else "node"
                radius = 15 if total_degree > 2 else 10
                
                svg_content += f'  <circle cx="{x}" cy="{y}" r="{radius}" class="{node_class}"/>\n'
                
                # Add label
                label = self.get_node_label(node)
                svg_content += f'  <text x="{x}" y="{y + 25}" class="node-label">{label}</text>\n'
            
            svg_content += '\n  <!-- Legend -->\n'
            svg_content += '''  <rect x="20" y="500" width="150" height="80" fill="white" stroke="#ccc" stroke-width="1"/>
  <text x="25" y="515" font-family="Arial, sans-serif" font-size="12" font-weight="bold">Legend:</text>
  <circle cx="35" cy="530" r="8" class="hub-node"/>
  <text x="50" y="535" font-family="Arial, sans-serif" font-size="10">Hub Nodes</text>
  <circle cx="35" cy="550" r="6" class="node"/>
  <text x="50" y="555" font-family="Arial, sans-serif" font-size="10">Regular Nodes</text>
  <line x1="25" y1="570" x2="45" y2="570" class="edge"/>
  <text x="50" y="575" font-family="Arial, sans-serif" font-size="10">Connections</text>
  
</svg>'''
            
            with open(output_file, 'w') as f:
                f.write(svg_content)
            
            print(f"SVG topology saved to: {output_file}")
            return True
            
        except Exception as e:
            print(f"Error generating SVG topology: {e}")
            return False

def main():
    """Main function for command line usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate Meshtastic network topology analysis (simplified version)')
    parser.add_argument('--traceroute-csv', default='traceroute_log.csv', 
                       help='Path to traceroute CSV file')
    parser.add_argument('--nodes-csv', default='nodes_log.csv',
                       help='Path to nodes CSV file')
    parser.add_argument('--output', default='network_topology',
                       help='Output file prefix (without extension)')
    parser.add_argument('--hours', type=int, default=24,
                       help='Hours of recent data to include')
    parser.add_argument('--stats', action='store_true',
                       help='Generate route statistics JSON')
    parser.add_argument('--format', choices=['text', 'svg', 'both'], default='both',
                       help='Output format')
    
    args = parser.parse_args()
    
    # Create analyzer
    analyzer = SimpleTracerouteAnalyzer(args.traceroute_csv, args.nodes_csv)
    
    success = True
    
    # Generate requested formats
    if args.format in ['text', 'both']:
        success &= analyzer.generate_text_topology(args.output + '.txt')
    
    if args.format in ['svg', 'both']:
        success &= analyzer.generate_simple_svg(args.output + '.svg')
    
    # Generate statistics if requested
    if args.stats:
        analyzer.generate_statistics_json(args.output + '_stats.json')
    
    if success:
        print("Network topology analysis completed successfully")
        return 0
    else:
        print("Failed to generate network topology analysis")
        return 1

if __name__ == "__main__":
    exit(main())