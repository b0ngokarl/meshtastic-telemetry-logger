#!/usr/bin/env python3

"""
Meshtastic Network Traceroute Visualization Generator
Generates network topology diagrams from traceroute data
"""

import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import networkx as nx
import numpy as np
import os
import sys
import json
from datetime import datetime, timedelta
from collections import defaultdict, Counter
import base64
from io import BytesIO

class TracerouteVisualizer:
    """Network topology visualizer for Meshtastic traceroute data"""
    
    def __init__(self, traceroute_csv="traceroute_log.csv", nodes_csv="nodes_log.csv"):
        self.traceroute_csv = traceroute_csv
        self.nodes_csv = nodes_csv
        self.graph = nx.DiGraph()
        self.node_names = {}
        self.node_positions = {}
        self.route_counts = defaultdict(int)
        
        # Load data
        self.load_node_names()
        self.load_traceroute_data()
    
    def load_node_names(self):
        """Load node names from nodes CSV for better labeling"""
        try:
            if os.path.exists(self.nodes_csv):
                nodes_df = pd.read_csv(self.nodes_csv)
                for _, row in nodes_df.iterrows():
                    node_id = row.get('ID', '')
                    user = row.get('User', '')
                    aka = row.get('AKA', '')
                    
                    # Create a nice display name
                    if user and aka:
                        display_name = f"{user}\n({aka})"
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
        """Load recent traceroute data and build network graph"""
        try:
            if not os.path.exists(self.traceroute_csv):
                print(f"Traceroute CSV file not found: {self.traceroute_csv}")
                return
            
            # Read traceroute data
            df = pd.read_csv(self.traceroute_csv)
            
            if df.empty:
                print("No traceroute data found")
                return
            
            # Filter to recent data
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            cutoff_time = datetime.now() - timedelta(hours=hours)
            recent_df = df[df['timestamp'] >= cutoff_time]
            
            print(f"Processing {len(recent_df)} recent traceroute records")
            
            # Build network graph from successful routes
            for _, row in recent_df.iterrows():
                if row['success'] == 'true' and row['hops'] != 'NO_ROUTE':
                    self.add_route_to_graph(row['target'], row['hops'])
            
            print(f"Built network graph with {self.graph.number_of_nodes()} nodes and {self.graph.number_of_edges()} edges")
            
        except Exception as e:
            print(f"Error loading traceroute data: {e}")
    
    def add_route_to_graph(self, target, hops_str):
        """Add a route path to the network graph"""
        if not hops_str or hops_str in ['NO_ROUTE', 'TIMEOUT', 'ERROR', 'PARSE_ERROR']:
            return
        
        # Parse hops (comma-separated node IDs)
        hops = [hop.strip() for hop in hops_str.split(',') if hop.strip()]
        
        if not hops:
            return
        
        # Add nodes to graph
        for hop in hops:
            if hop not in self.graph:
                self.graph.add_node(hop)
        
        # Add edges between consecutive hops
        for i in range(len(hops) - 1):
            from_node = hops[i]
            to_node = hops[i + 1]
            
            # Count route usage for edge weighting
            route_key = f"{from_node}->{to_node}"
            self.route_counts[route_key] += 1
            
            # Add or update edge
            if self.graph.has_edge(from_node, to_node):
                self.graph[from_node][to_node]['weight'] += 1
            else:
                self.graph.add_edge(from_node, to_node, weight=1)
    
    def get_node_label(self, node_id):
        """Get a display label for a node"""
        if node_id in self.node_names:
            return self.node_names[node_id]
        else:
            # Use short form of node ID if no name available
            return node_id[-4:] if len(node_id) > 4 else node_id
    
    def generate_network_topology(self, output_file="network_topology.png", figsize=(16, 12)):
        """Generate network topology visualization"""
        if self.graph.number_of_nodes() == 0:
            print("No network topology data to visualize")
            return False
        
        try:
            # Create figure
            fig, ax = plt.subplots(figsize=figsize, dpi=300)
            fig.patch.set_facecolor('white')
            
            # Use spring layout for better node positioning
            try:
                pos = nx.spring_layout(self.graph, k=3, iterations=50, seed=42)
            except:
                # Fallback to simple circular layout
                pos = nx.circular_layout(self.graph)
            
            # Draw edges with varying thickness based on usage
            edges = self.graph.edges()
            weights = [self.graph[u][v]['weight'] for u, v in edges]
            max_weight = max(weights) if weights else 1
            
            # Normalize edge weights for visualization
            edge_widths = [2 + (w / max_weight) * 6 for w in weights]
            edge_colors = ['#666666' for _ in weights]
            
            nx.draw_networkx_edges(
                self.graph, pos, 
                width=edge_widths,
                edge_color=edge_colors,
                alpha=0.7,
                arrows=True,
                arrowsize=20,
                arrowstyle='->',
                connectionstyle='arc3,rad=0.1'
            )
            
            # Draw nodes
            node_sizes = []
            node_colors = []
            
            for node in self.graph.nodes():
                # Size based on degree (how connected the node is)
                degree = self.graph.degree(node)
                size = 500 + degree * 200
                node_sizes.append(size)
                
                # Color based on type (could be enhanced with more metadata)
                if degree > 2:
                    node_colors.append('#FF6B6B')  # Hub nodes in red
                elif degree > 1:
                    node_colors.append('#4ECDC4')  # Intermediate nodes in teal
                else:
                    node_colors.append('#45B7D1')  # End nodes in blue
            
            nx.draw_networkx_nodes(
                self.graph, pos,
                node_size=node_sizes,
                node_color=node_colors,
                alpha=0.8
            )
            
            # Draw labels
            labels = {node: self.get_node_label(node) for node in self.graph.nodes()}
            nx.draw_networkx_labels(
                self.graph, pos,
                labels=labels,
                font_size=8,
                font_weight='bold',
                font_color='white'
            )
            
            # Add edge labels for weights (on high-usage connections only)
            edge_labels = {}
            for u, v in self.graph.edges():
                weight = self.graph[u][v]['weight']
                if weight > 1:  # Only show labels for multi-use routes
                    edge_labels[(u, v)] = str(weight)
            
            if edge_labels:
                nx.draw_networkx_edge_labels(
                    self.graph, pos,
                    edge_labels=edge_labels,
                    font_size=7,
                    font_color='red',
                    bbox=dict(boxstyle='round,pad=0.1', facecolor='white', alpha=0.8)
                )
            
            # Set title and formatting
            plt.title('Meshtastic Network Topology\n(Based on Traceroute Data)', 
                     fontsize=16, fontweight='bold', pad=20)
            
            # Add legend
            legend_elements = [
                plt.Line2D([0], [0], marker='o', color='w', markerfacecolor='#FF6B6B', 
                          markersize=10, label='Hub Nodes (>2 connections)'),
                plt.Line2D([0], [0], marker='o', color='w', markerfacecolor='#4ECDC4', 
                          markersize=10, label='Intermediate Nodes'),
                plt.Line2D([0], [0], marker='o', color='w', markerfacecolor='#45B7D1', 
                          markersize=10, label='End Nodes'),
                plt.Line2D([0], [0], color='#666666', linewidth=3, label='Route Paths'),
            ]
            
            ax.legend(handles=legend_elements, loc='upper left', bbox_to_anchor=(0, 1))
            
            # Add statistics text
            stats_text = f"""Network Statistics:
• Nodes: {self.graph.number_of_nodes()}
• Routes: {self.graph.number_of_edges()}
• Avg. Connections: {np.mean([d for n, d in self.graph.degree()]):.1f}
• Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}"""
            
            ax.text(0.02, 0.02, stats_text, transform=ax.transAxes, 
                   bbox=dict(boxstyle='round,pad=0.5', facecolor='lightgray', alpha=0.8),
                   fontsize=9, verticalalignment='bottom')
            
            # Remove axes
            ax.set_axis_off()
            
            # Tight layout
            plt.tight_layout()
            
            # Save the plot
            plt.savefig(output_file, dpi=300, bbox_inches='tight', 
                       facecolor='white', edgecolor='none')
            
            print(f"Network topology saved to: {output_file}")
            
            # Also save as base64 for HTML embedding
            self.save_as_base64(fig, output_file.replace('.png', '_base64.txt'))
            
            plt.close()
            return True
            
        except Exception as e:
            print(f"Error generating network topology: {e}")
            return False
    
    def save_as_base64(self, fig, output_file):
        """Save plot as base64 encoded string for HTML embedding"""
        try:
            buffer = BytesIO()
            fig.savefig(buffer, format='png', dpi=300, bbox_inches='tight',
                       facecolor='white', edgecolor='none')
            buffer.seek(0)
            
            # Encode to base64
            img_base64 = base64.b64encode(buffer.getvalue()).decode()
            
            # Save to file
            with open(output_file, 'w') as f:
                f.write(img_base64)
            
            print(f"Base64 encoded image saved to: {output_file}")
            
        except Exception as e:
            print(f"Error saving base64 image: {e}")
    
    def generate_route_statistics(self, output_file="route_statistics.json"):
        """Generate route usage statistics"""
        try:
            stats = {
                'timestamp': datetime.now().isoformat(),
                'network_stats': {
                    'total_nodes': self.graph.number_of_nodes(),
                    'total_routes': self.graph.number_of_edges(),
                    'avg_connections': np.mean([d for n, d in self.graph.degree()]) if self.graph.nodes() else 0
                },
                'node_stats': {},
                'route_usage': dict(self.route_counts),
                'topology_analysis': self.analyze_topology()
            }
            
            # Add per-node statistics
            for node in self.graph.nodes():
                degree = self.graph.degree(node)
                in_degree = self.graph.in_degree(node)
                out_degree = self.graph.out_degree(node)
                
                stats['node_stats'][node] = {
                    'display_name': self.get_node_label(node),
                    'total_connections': degree,
                    'incoming_routes': in_degree,
                    'outgoing_routes': out_degree,
                    'is_hub': degree > 2,
                    'is_endpoint': degree == 1
                }
            
            # Save to JSON file
            with open(output_file, 'w') as f:
                json.dump(stats, f, indent=2, default=str)
            
            print(f"Route statistics saved to: {output_file}")
            return stats
            
        except Exception as e:
            print(f"Error generating route statistics: {e}")
            return {}
    
    def analyze_topology(self):
        """Analyze network topology characteristics"""
        if self.graph.number_of_nodes() == 0:
            return {}
        
        try:
            analysis = {}
            
            # Connectivity analysis
            analysis['is_connected'] = nx.is_weakly_connected(self.graph)
            analysis['num_components'] = nx.number_weakly_connected_components(self.graph)
            
            # Hub identification
            degrees = dict(self.graph.degree())
            max_degree = max(degrees.values()) if degrees else 0
            hubs = [node for node, degree in degrees.items() if degree > 2]
            analysis['hub_nodes'] = hubs
            analysis['max_connections'] = max_degree
            
            # Path analysis
            if nx.is_weakly_connected(self.graph):
                try:
                    analysis['diameter'] = nx.diameter(self.graph.to_undirected())
                    analysis['avg_path_length'] = nx.average_shortest_path_length(self.graph.to_undirected())
                except:
                    analysis['diameter'] = 'N/A'
                    analysis['avg_path_length'] = 'N/A'
            else:
                analysis['diameter'] = 'Disconnected'
                analysis['avg_path_length'] = 'Disconnected'
            
            # Centrality measures (for small networks)
            if self.graph.number_of_nodes() <= 50:
                try:
                    centrality = nx.betweenness_centrality(self.graph)
                    most_central = max(centrality, key=centrality.get) if centrality else None
                    analysis['most_central_node'] = most_central
                    analysis['centrality_score'] = centrality.get(most_central, 0) if most_central else 0
                except:
                    analysis['most_central_node'] = None
                    analysis['centrality_score'] = 0
            
            return analysis
            
        except Exception as e:
            print(f"Error in topology analysis: {e}")
            return {}

def main():
    """Main function for command line usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Generate Meshtastic network topology visualization')
    parser.add_argument('--traceroute-csv', default='traceroute_log.csv', 
                       help='Path to traceroute CSV file')
    parser.add_argument('--nodes-csv', default='nodes_log.csv',
                       help='Path to nodes CSV file')
    parser.add_argument('--output', default='network_topology.png',
                       help='Output image file path')
    parser.add_argument('--hours', type=int, default=24,
                       help='Hours of recent data to include')
    parser.add_argument('--figsize', nargs=2, type=int, default=[16, 12],
                       help='Figure size (width height)')
    parser.add_argument('--stats', action='store_true',
                       help='Generate route statistics JSON')
    
    args = parser.parse_args()
    
    # Create visualizer
    visualizer = TracerouteVisualizer(args.traceroute_csv, args.nodes_csv)
    
    # Generate visualization
    success = visualizer.generate_network_topology(
        output_file=args.output,
        figsize=tuple(args.figsize)
    )
    
    # Generate statistics if requested
    if args.stats:
        stats_file = args.output.replace('.png', '_stats.json')
        visualizer.generate_route_statistics(stats_file)
    
    if success:
        print("Network topology visualization completed successfully")
        return 0
    else:
        print("Failed to generate network topology visualization")
        return 1

if __name__ == "__main__":
    exit(main())