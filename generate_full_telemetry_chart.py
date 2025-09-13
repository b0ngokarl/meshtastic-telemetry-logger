#!/usr/bin/env python3
"""
Generate comprehensive telemetry charts for specified nodes showing all available metrics:
- Battery level, Voltage, Channel utilization, Transmission utilization, Uptime
Reads configuration from .env file, with optional command-line overrides

Usage:
    python generate_full_telemetry_chart.py                              # Use .env configuration
    python generate_full_telemetry_chart.py --nodes "!2df67288,!a0cc8008"  # Override nodes
    python generate_full_telemetry_chart.py --nodes "!2df67288" --names "My Node"  # Single node with custom name
"""

import csv
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime
import pandas as pd
import sys
import os
import argparse
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


def auto_update_node_names():
    """Automatically update CHART_NODE_NAMES from nodes_log.csv"""
    def get_node_names_from_csv(chart_nodes, csv_file='nodes_log.csv'):
        """Extract node names from nodes_log.csv for the given node IDs"""
        node_names = {}
        
        if not os.path.exists(csv_file):
            return node_names
        
        try:
            with open(csv_file, 'r') as file:
                reader = csv.DictReader(file)
                for row in reader:
                    node_id = row.get('ID', '').strip()
                    node_name = row.get('User', '').strip()
                    node_aka = row.get('AKA', '').strip()
                    
                    if node_id in chart_nodes:
                        # Use AKA if available and short, otherwise use User name
                        if node_aka and len(node_aka) <= 8:
                            display_name = f"{node_name} ({node_aka})"
                        else:
                            display_name = node_name
                        
                        node_names[node_id] = display_name
                        
        except Exception as e:
            print(f"Warning: Could not auto-update node names: {e}")
        
        return node_names

    def update_env_file(chart_nodes, node_names, env_file='.env'):
        """Update the .env file with automatically generated CHART_NODE_NAMES"""
        
        # Generate the names list in the same order as chart_nodes
        names_list = []
        for node_id in chart_nodes:
            if node_id in node_names:
                names_list.append(node_names[node_id])
            else:
                # Fallback to node ID if name not found
                names_list.append(f"Node {node_id}")
        
        new_names_value = ','.join(names_list)
        
        # Read the current .env file
        with open(env_file, 'r') as file:
            lines = file.readlines()
        
        # Update the CHART_NODE_NAMES line
        updated = False
        for i, line in enumerate(lines):
            if line.strip().startswith('CHART_NODE_NAMES='):
                lines[i] = f'CHART_NODE_NAMES="{new_names_value}"\n'
                updated = True
                break
        
        # If CHART_NODE_NAMES doesn't exist, add it after CHART_NODES
        if not updated:
            for i, line in enumerate(lines):
                if line.strip().startswith('CHART_NODES='):
                    lines.insert(i + 1, f'CHART_NODE_NAMES="{new_names_value}"\n')
                    updated = True
                    break
        
        # Write the updated file
        if updated:
            with open(env_file, 'w') as file:
                file.writelines(lines)
            return True
        
        return False

    # Load current configuration to avoid infinite recursion
    config = {}
    
    if os.path.exists('.env'):
        try:
            with open('.env', 'r') as file:
                for line in file:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        value = value.strip().strip('"').strip("'")
                        config[key.strip()] = value
        except Exception:
            return  # Silently fail if can't read config
    
    chart_nodes_str = config.get('CHART_NODES', '')
    
    if chart_nodes_str:
        chart_nodes = [node.strip() for node in chart_nodes_str.split(',') if node.strip()]
        if chart_nodes:
            node_names = get_node_names_from_csv(chart_nodes)
            if node_names:
                update_env_file(chart_nodes, node_names)
                print("✅ Auto-updated chart node names from nodes_log.csv")


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
    
    # Create mapping with all telemetry fields
    node_config = {}
    for i, node in enumerate(chart_nodes):
        node_config[node] = {
            'name': chart_names[i] if i < len(chart_names) else f"Node {node}",
            'timestamps': [],
            'battery': [],
            'voltage': [],
            'chutil': [],
            'txutil': [],
            'uptime': []
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
                            
                            # Parse all telemetry values
                            battery_val = float(battery) if battery else None
                            voltage_val = float(voltage) if voltage else None
                            chutil = float(channel_util) if channel_util else None
                            txutil = float(tx_util) if tx_util else None
                            uptime_val = float(uptime) / 3600.0 if uptime else None  # Convert to hours
                            
                            # Store all available data
                            node_config[address]['timestamps'].append(timestamp)
                            node_config[address]['battery'].append(battery_val)
                            node_config[address]['voltage'].append(voltage_val)
                            node_config[address]['chutil'].append(chutil)
                            node_config[address]['txutil'].append(txutil)
                            node_config[address]['uptime'].append(uptime_val)
                            
                        except (ValueError, TypeError):
                            continue
    except FileNotFoundError:
        print(f"Error: {csv_file} not found")
        sys.exit(1)
    
    return node_config

def create_chart(data, output_prefix="node_telemetry"):
    """Create and save the comprehensive telemetry chart"""
    # Generate title based on nodes
    node_names = [node_data['name'] for node_data in data.values() if node_data['timestamps']]
    if len(node_names) == 1:
        title = f"{node_names[0]} - Full Telemetry"
    elif len(node_names) == 2:
        title = f"{node_names[0]} vs {node_names[1]} - Telemetry Comparison"
    else:
        title = f"Multiple Nodes - Full Telemetry"
    
    # Create figure with 5 subplots (battery, voltage, channel util, tx util, uptime)
    fig, axes = plt.subplots(5, 1, figsize=(16, 20))
    fig.suptitle(title, fontsize=18, fontweight='bold')
    
    # Generate colors for each node
    colors = ['#2E8B57', '#4682B4', '#DC143C', '#FF8C00', '#9932CC', '#008B8B', '#B22222', '#228B22']
    color_map = {}
    for i, node_id in enumerate(data.keys()):
        color_map[node_id] = colors[i % len(colors)]
    
    # Plot 1: Battery Level
    ax1 = axes[0]
    ax1.set_title('Battery Level (%)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps'] and any(b is not None for b in node_data['battery']):
            # Filter out None values
            valid_data = [(t, b) for t, b in zip(node_data['timestamps'], node_data['battery']) if b is not None]
            if valid_data:
                timestamps, battery_values = zip(*valid_data)
                ax1.plot(timestamps, battery_values, 
                        label=node_data['name'], color=color_map[node_id], 
                        linewidth=2, marker='o', markersize=4)
    ax1.set_ylabel('Battery Level (%)', fontsize=12)
    ax1.grid(True, alpha=0.3)
    ax1.legend(fontsize=10)
    ax1.set_ylim(0, 100)
    
    # Plot 2: Voltage
    ax2 = axes[1]
    ax2.set_title('Voltage (V)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps'] and any(v is not None for v in node_data['voltage']):
            # Filter out None values
            valid_data = [(t, v) for t, v in zip(node_data['timestamps'], node_data['voltage']) if v is not None]
            if valid_data:
                timestamps, voltage_values = zip(*valid_data)
                ax2.plot(timestamps, voltage_values, 
                        label=node_data['name'], color=color_map[node_id], 
                        linewidth=2, marker='s', markersize=4)
    ax2.set_ylabel('Voltage (V)', fontsize=12)
    ax2.grid(True, alpha=0.3)
    ax2.legend(fontsize=10)
    # Dynamic voltage range based on data
    all_voltages = [v for node_data in data.values() for v in node_data['voltage'] if v is not None]
    if all_voltages:
        min_v, max_v = min(all_voltages), max(all_voltages)
        ax2.set_ylim(min_v * 0.95, max_v * 1.05)
    
    # Plot 3: Channel Utilization
    ax3 = axes[2]
    ax3.set_title('Channel Utilization (%)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps'] and any(c is not None for c in node_data['chutil']):
            # Filter out None values
            valid_data = [(t, c) for t, c in zip(node_data['timestamps'], node_data['chutil']) if c is not None]
            if valid_data:
                timestamps, chutil_values = zip(*valid_data)
                ax3.plot(timestamps, chutil_values, 
                        label=node_data['name'], color=color_map[node_id], 
                        linewidth=2, marker='^', markersize=4)
    ax3.set_ylabel('Channel Utilization (%)', fontsize=12)
    ax3.grid(True, alpha=0.3)
    ax3.legend(fontsize=10)
    all_chutil = [c for node_data in data.values() for c in node_data['chutil'] if c is not None]
    if all_chutil:
        max_chutil = max(all_chutil)
        ax3.set_ylim(0, max_chutil * 1.1)
    else:
        ax3.set_ylim(0, 100)
    
    # Plot 4: Transmission Utilization
    ax4 = axes[3]
    ax4.set_title('Transmission Utilization (%)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps'] and any(t is not None for t in node_data['txutil']):
            # Filter out None values
            valid_data = [(t, tx) for t, tx in zip(node_data['timestamps'], node_data['txutil']) if tx is not None]
            if valid_data:
                timestamps, txutil_values = zip(*valid_data)
                ax4.plot(timestamps, txutil_values, 
                        label=node_data['name'], color=color_map[node_id], 
                        linewidth=2, marker='d', markersize=4)
    ax4.set_ylabel('Transmission Utilization (%)', fontsize=12)
    ax4.grid(True, alpha=0.3)
    ax4.legend(fontsize=10)
    all_txutil = [t for node_data in data.values() for t in node_data['txutil'] if t is not None]
    if all_txutil:
        max_txutil = max(all_txutil)
        ax4.set_ylim(0, max_txutil * 1.1)
    else:
        ax4.set_ylim(0, 10)
    
    # Plot 5: Uptime
    ax5 = axes[4]
    ax5.set_title('Uptime (Hours)', fontsize=14, fontweight='bold')
    for node_id, node_data in data.items():
        if node_data['timestamps'] and any(u is not None for u in node_data['uptime']):
            # Filter out None values
            valid_data = [(t, u) for t, u in zip(node_data['timestamps'], node_data['uptime']) if u is not None]
            if valid_data:
                timestamps, uptime_values = zip(*valid_data)
                ax5.plot(timestamps, uptime_values, 
                        label=node_data['name'], color=color_map[node_id], 
                        linewidth=2, marker='x', markersize=4)
    ax5.set_ylabel('Uptime (Hours)', fontsize=12)
    ax5.set_xlabel('Time', fontsize=12)
    ax5.grid(True, alpha=0.3)
    ax5.legend(fontsize=10)
    all_uptime = [u for node_data in data.values() for u in node_data['uptime'] if u is not None]
    if all_uptime:
        max_uptime = max(all_uptime)
        ax5.set_ylim(0, max_uptime * 1.1)
    
    # Format x-axis for all plots
    for ax in axes:
        ax.xaxis.set_major_formatter(mdates.DateFormatter('%m-%d %H:%M'))
        ax.xaxis.set_major_locator(mdates.HourLocator(interval=6))
        plt.setp(ax.xaxis.get_majorticklabels(), rotation=45)
    
    plt.tight_layout()
    
    # Save the chart
    output_file = f'{output_prefix}_chart.png'
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Comprehensive telemetry chart saved as: {output_file}")
    
    # Also save as SVG for scalability
    svg_file = f'{output_prefix}_chart.svg'
    plt.savefig(svg_file, bbox_inches='tight')
    print(f"SVG version saved as: {svg_file}")
    
    plt.close()
    
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
    parser = argparse.ArgumentParser(description='Generate comprehensive telemetry charts from node data')
    parser.add_argument('--nodes', type=str, help='Comma-separated list of node IDs (overrides .env)')
    parser.add_argument('--names', type=str, help='Comma-separated list of node names (must match nodes count)')
    parser.add_argument('--output', type=str, help='Output filename prefix (default: auto-generated)')
    parser.add_argument('--csv', type=str, help='Telemetry CSV file path (overrides .env)')
    
    args = parser.parse_args()
    
    print("Generating comprehensive telemetry chart...")
    
    # Auto-update node names from CSV if not overridden by command line
    if not args.names:
        auto_update_node_names()
    
    # Load configuration
    config = load_env_file()
    
    # Override configuration with command-line arguments if provided
    if args.nodes:
        config['CHART_NODES'] = args.nodes
    if args.names:
        config['CHART_NODE_NAMES'] = args.names
    if args.csv:
        config['TELEMETRY_CSV'] = args.csv
    
    # Parse chart configuration
    node_config = parse_chart_config(config)
    
    if not node_config:
        print("No nodes configured for chart generation")
        print("Please set CHART_NODES in your .env file or use --nodes argument")
        print("Example: python generate_full_telemetry_chart.py --nodes '!2df67288,!a0cc8008'")
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
    
    # Generate output filename prefix
    if args.output:
        output_prefix = args.output
    elif len(data) == 1:
        first_node = list(data.keys())[0]
        output_prefix = first_node.replace('!', '').replace(':', '_')
    else:
        output_prefix = "multi_node_telemetry"
    
    # Create chart
    create_chart(data, output_prefix)
    
    print(f"\nComprehensive telemetry chart generation complete!")
    if args.nodes or args.names or args.csv:
        print("Configuration: Command-line arguments used")
    else:
        print("Configuration loaded from: .env")
    print(f"Telemetry data source: {csv_file}")
    print(f"Charts include: Battery Level, Voltage, Channel Utilization, Transmission Utilization, Uptime")

if __name__ == "__main__":
    main()
