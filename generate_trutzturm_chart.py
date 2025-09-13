#!/usr/bin/env python3
"""
Generate chart for specified nodes showing channel utilization and transmission utilization
Reads configuration from .env file
"""

import csv
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime
import pandas as pd
import sys
import os
from pathlib import Path

def load_env_file():
    """Load configuration from .env file"""
    env_path = Path('.env')
    config = {}
    
    if not env_path.exists():
        print("Error: .env file not found. Please create one based on .env.example")
        sys.exit(1)
    
    try:
        with open(env_path, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip().strip('"').strip("'")
                    config[key.strip()] = value
    except Exception as e:
        print(f"Error reading .env file: {e}")
        sys.exit(1)
    
    return config

def parse_chart_config(config):
    """Parse chart configuration from .env file"""
    chart_nodes = config.get('CHART_NODES', '').split(',')
    chart_names = config.get('CHART_NODE_NAMES', '').split(',')
    
    # Clean up the lists
    chart_nodes = [node.strip() for node in chart_nodes if node.strip()]
    chart_names = [name.strip() for name in chart_names if name.strip()]
    
    # If no specific chart nodes defined, fall back to monitored nodes
    if not chart_nodes:
        monitored_nodes = config.get('MONITORED_NODES', '').split(',')
        chart_nodes = [node.strip() for node in monitored_nodes if node.strip()]
    
    # If names don't match nodes count, generate default names
    if len(chart_names) != len(chart_nodes):
        chart_names = [f"Node {node}" for node in chart_nodes]
    
    # Create mapping
    node_config = {}
    for i, node in enumerate(chart_nodes):
        node_config[node] = {
            'name': chart_names[i] if i < len(chart_names) else f"Node {node}",
            'timestamps': [],
            'chutil': [],
            'txutil': []
        }
    
    return node_config

def load_telemetry_data(node_config, csv_file):
    """Load telemetry data from CSV file for specified nodes"""
    try:
        with open(csv_file, 'r') as file:
            reader = csv.reader(file)
            next(reader)  # Skip header
            
            for row in reader:
                if len(row) >= 8:
                    timestamp_str, address, status, battery, voltage, channel_util, tx_util, uptime = row
                    
                    # Only process successful readings for our configured nodes
                    if status == 'success' and address in node_config:
                        try:
                            # Parse timestamp
                            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                            
                            # Parse utilization values
                            chutil = float(channel_util) if channel_util else None
                            txutil = float(tx_util) if tx_util else None
                            
                            if chutil is not None and txutil is not None:
                                node_config[address]['timestamps'].append(timestamp)
                                node_config[address]['chutil'].append(chutil)
                                node_config[address]['txutil'].append(txutil)
                        except (ValueError, TypeError):
                            continue
    except FileNotFoundError:
        print(f"Error: {csv_file} not found")
        sys.exit(1)
    
    return node_config

def create_chart(data, output_prefix="node_utilization"):
    """Create and save the chart"""
    # Generate title based on nodes
    node_names = [node_data['name'] for node_data in data.values() if node_data['timestamps']]
    if len(node_names) == 1:
        title = f"{node_names[0]} - Channel & Transmission Utilization"
    elif len(node_names) == 2:
        title = f"{node_names[0]} vs {node_names[1]} - Utilization Comparison"
    else:
        title = f"Multiple Nodes - Channel & Transmission Utilization"
    
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))
    fig.suptitle(title, fontsize=16, fontweight='bold')
    
    # Generate colors for each node
    colors = ['#2E8B57', '#4682B4', '#DC143C', '#FF8C00', '#9932CC', '#008B8B', '#B22222', '#228B22']
    color_map = {}
    for i, node_id in enumerate(data.keys()):
        color_map[node_id] = colors[i % len(colors)]
    
    # Plot 1: Channel Utilization
    ax1.set_title('Channel Utilization (%)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps']:
            ax1.plot(node_data['timestamps'], node_data['chutil'], 
                    label=node_data['name'], color=color_map[node_id], 
                    linewidth=2, marker='o', markersize=4)
    
    ax1.set_ylabel('Channel Utilization (%)', fontsize=12)
    ax1.grid(True, alpha=0.3)
    ax1.legend(fontsize=10)
    max_chutil = max([max(node_data['chutil']) if node_data['chutil'] else 0 for node_data in data.values()])
    ax1.set_ylim(0, max_chutil * 1.1 if max_chutil > 0 else 100)
    
    # Plot 2: Transmission Utilization
    ax2.set_title('Transmission Utilization (%)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps']:
            ax2.plot(node_data['timestamps'], node_data['txutil'], 
                    label=node_data['name'], color=color_map[node_id], 
                    linewidth=2, marker='s', markersize=4)
    
    ax2.set_ylabel('Transmission Utilization (%)', fontsize=12)
    ax2.set_xlabel('Time', fontsize=12)
    ax2.grid(True, alpha=0.3)
    ax2.legend(fontsize=10)
    max_txutil = max([max(node_data['txutil']) if node_data['txutil'] else 0 for node_data in data.values()])
    ax2.set_ylim(0, max_txutil * 1.1 if max_txutil > 0 else 10)
    
    # Format x-axis for both plots
    for ax in [ax1, ax2]:
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%m-%d %H:%M'))
        ax.xaxis.set_major_locator(mdates.HourLocator(interval=6))
        plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)
    
    plt.tight_layout()
    
    # Save the chart
    output_file = f'{output_prefix}_chart.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Chart saved as: {output_file}")
    
    # Also save as SVG for vector graphics
    output_svg = f'{output_prefix}_chart.svg'
    plt.savefig(output_svg, format='svg', bbox_inches='tight')
    print(f"Vector chart saved as: {output_svg}")
    
    # Show some statistics
    print("\n=== Data Summary ===")
    for node_id, node_data in data.items():
        if node_data['timestamps']:
            print(f"\n{node_data['name']} ({node_id}):")
            print(f"  Data points: {len(node_data['timestamps'])}")
            if node_data['timestamps']:
                print(f"  Time range: {min(node_data['timestamps'])} to {max(node_data['timestamps'])}")
                print(f"  Channel Util - Min: {min(node_data['chutil']):.2f}%, Max: {max(node_data['chutil']):.2f}%, Avg: {sum(node_data['chutil'])/len(node_data['chutil']):.2f}%")
                print(f"  TX Util - Min: {min(node_data['txutil']):.2f}%, Max: {max(node_data['txutil']):.2f}%, Avg: {sum(node_data['txutil'])/len(node_data['txutil']):.2f}%")
    
    return output_file

def main():
    print("Generating node utilization chart from .env configuration...")
    
    # Load configuration
    config = load_env_file()
    
    # Parse chart configuration
    node_config = parse_chart_config(config)
    
    if not node_config:
        print("No nodes configured for chart generation in .env file")
        print("Please set CHART_NODES and optionally CHART_NODE_NAMES in your .env file")
        sys.exit(1)
    
    print(f"Configured nodes for charting: {list(node_config.keys())}")
    
    # Get CSV filename from config or use default
    csv_file = config.get('TELEMETRY_CSV', 'telemetry_log.csv')
    
    # Load telemetry data
    data = load_telemetry_data(node_config, csv_file)
    
    # Check if we have data
    total_points = sum(len(node_data['timestamps']) for node_data in data.values())
    if total_points == 0:
        print("No telemetry data found for configured nodes")
        print(f"Configured nodes: {list(data.keys())}")
        sys.exit(1)
    
    # Generate output filename prefix based on first node or generic name
    if len(data) == 1:
        first_node = list(data.keys())[0]
        output_prefix = first_node.replace('!', '').replace(':', '_')
    else:
        output_prefix = "multi_node_utilization"
    
    # Create chart
    output_file = create_chart(data, output_prefix)
    
    print(f"\nChart generation complete! Output: {output_file}")
    print(f"Configuration loaded from: .env")
    print(f"Telemetry data source: {csv_file}")

if __name__ == "__main__":
    main()
