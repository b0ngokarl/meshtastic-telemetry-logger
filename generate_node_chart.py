#!/usr/bin/env python3
"""
Generate chart for specified nodes showing channel utilization and transmission utilization
Reads configuration from .env file, with optional command-line overrides

Usage:
    python generate_node_chart.py                              # Use .env configuration
    python generate_node_chart.py --nodes "!2df67288,!a0cc8008"  # Override nodes
    python generate_node_chart.py --nodes "!2df67288" --names "My Node"  # Single node with custom name
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
    env_path = Path('.env')
    
    if env_path.exists():
        try:
            with open(env_path, 'r') as file:
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

def extract_short_name(full_name):
    """Extract short name from full node name, e.g., 'TRZT' from 'DL0TRZ Trutzturm Oppenheim (TRZT)'"""
    # Look for text in parentheses first
    if '(' in full_name and ')' in full_name:
        start = full_name.rfind('(') + 1
        end = full_name.rfind(')')
        short_name = full_name[start:end].strip()
        if short_name and len(short_name) <= 8:
            return short_name
    
    # Fallback: use first 4 characters of the last word
    words = full_name.split()
    if words:
        return words[-1][:4].upper()
    
    return full_name[:4].upper()

def calculate_recent_averages(timestamps, values, metric_name):
    """Calculate averages for now, 3h, 12h, and 24h periods"""
    if not timestamps or not values or len(timestamps) != len(values):
        return ""
    
    from datetime import timedelta
    import statistics
    
    now = datetime.now(timestamps[0].tzinfo) if timestamps[0].tzinfo else datetime.now()
    
    # Get current value (most recent)
    current_value = None
    valid_data = [(t, v) for t, v in zip(timestamps, values) if v is not None]
    if valid_data:
        # Sort by timestamp to get the most recent
        valid_data.sort(key=lambda x: x[0])
        current_value = valid_data[-1][1]
    
    # Filter data for each time period
    periods = {'3h': 3, '12h': 12, '24h': 24}
    averages = []
    
    # Add current value first
    if current_value is not None:
        if metric_name in ['chutil', 'txutil']:
            averages.append(f"now:{current_value:.1f}%")
        else:
            averages.append(f"now:{current_value:.1f}")
    
    # Add averages for time periods
    for period_name, hours in periods.items():
        cutoff_time = now - timedelta(hours=hours)
        recent_values = [v for t, v in zip(timestamps, values) 
                        if v is not None and t >= cutoff_time]
        
        if recent_values:
            avg = statistics.mean(recent_values)
            if metric_name in ['chutil', 'txutil']:
                averages.append(f"{period_name}:{avg:.1f}%")
            else:
                averages.append(f"{period_name}:{avg:.1f}")
    
    return " | ".join(averages) if averages else ""

def create_enhanced_label(node_data, metric_name):
    """Create enhanced label with short name and averages"""
    short_name = extract_short_name(node_data['name'])
    
    # Get the appropriate data for the metric
    if metric_name == 'chutil':
        values = node_data['chutil']
    elif metric_name == 'txutil':
        values = node_data['txutil']
    else:
        values = []
    
    averages = calculate_recent_averages(node_data['timestamps'], values, metric_name)
    
    if averages:
        return f"{short_name} ({averages})"
    else:
        return short_name

def calculate_total_utilization_averages(data, metric_name):
    """Calculate total averages across all nodes for utilization metrics"""
    if not data:
        return [], []
    
    # Collect all timestamp-value pairs from all nodes
    all_data_points = []
    for node_data in data.values():
        if metric_name == 'chutil':
            values = node_data['chutil']
        elif metric_name == 'txutil':
            values = node_data['txutil']
        else:
            continue
            
        for timestamp, value in zip(node_data['timestamps'], values):
            if value is not None:
                all_data_points.append((timestamp, value))
    
    if not all_data_points:
        return [], []
    
    # Sort by timestamp
    all_data_points.sort(key=lambda x: x[0])
    
    # Group by timestamp and calculate averages
    from collections import defaultdict
    import statistics
    
    timestamp_groups = defaultdict(list)
    for timestamp, value in all_data_points:
        # Round timestamp to nearest minute for grouping
        rounded_time = timestamp.replace(second=0, microsecond=0)
        timestamp_groups[rounded_time].append(value)
    
    # Calculate average for each timestamp
    avg_timestamps = []
    avg_values = []
    for timestamp in sorted(timestamp_groups.keys()):
        values = timestamp_groups[timestamp]
        avg_value = statistics.mean(values)
        avg_timestamps.append(timestamp)
        avg_values.append(avg_value)
    
    return avg_timestamps, avg_values

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
    
    # Plot individual nodes
    for node_id, node_data in data.items():
        if node_data['timestamps']:
            ax1.plot(node_data['timestamps'], node_data['chutil'], 
                    label=create_enhanced_label(node_data, 'chutil'), color=color_map[node_id], 
                    linewidth=2, marker='o', markersize=4)
    
    # Add total average line
    total_timestamps, total_chutil = calculate_total_utilization_averages(data, 'chutil')
    if total_timestamps and total_chutil:
        total_averages = calculate_recent_averages(total_timestamps, total_chutil, 'chutil')
        total_label = f"TOTAL AVG ({total_averages})" if total_averages else "TOTAL AVG"
        ax1.plot(total_timestamps, total_chutil, 
                label=total_label, color='black', 
                linewidth=3, linestyle='--', marker='o', markersize=3)
    
    ax1.set_ylabel('Channel Utilization (%)', fontsize=12)
    ax1.grid(True, alpha=0.3)
    ax1.legend(fontsize=10)
    max_chutil = max([max(node_data['chutil']) if node_data['chutil'] else 0 for node_data in data.values()])
    if total_chutil and total_chutil:
        max_chutil = max(max_chutil, max(total_chutil))
    ax1.set_ylim(0, max_chutil * 1.1 if max_chutil > 0 else 100)
    
    # Plot 2: Transmission Utilization
    ax2.set_title('Transmission Utilization (%)', fontsize=14, fontweight='bold')
    
    # Plot individual nodes
    for node_id, node_data in data.items():
        if node_data['timestamps']:
            ax2.plot(node_data['timestamps'], node_data['txutil'], 
                    label=create_enhanced_label(node_data, 'txutil'), color=color_map[node_id], 
                    linewidth=2, marker='s', markersize=4)
    
    # Add total average line
    total_timestamps, total_txutil = calculate_total_utilization_averages(data, 'txutil')
    if total_timestamps and total_txutil:
        total_averages = calculate_recent_averages(total_timestamps, total_txutil, 'txutil')
        total_label = f"TOTAL AVG ({total_averages})" if total_averages else "TOTAL AVG"
        ax2.plot(total_timestamps, total_txutil, 
                label=total_label, color='black', 
                linewidth=3, linestyle='--', marker='o', markersize=3)
    
    ax2.set_ylabel('Transmission Utilization (%)', fontsize=12)
    ax2.set_xlabel('Time', fontsize=12)
    ax2.grid(True, alpha=0.3)
    ax2.legend(fontsize=10)
    max_txutil = max([max(node_data['txutil']) if node_data['txutil'] else 0 for node_data in data.values()])
    if total_txutil and total_txutil:
        max_txutil = max(max_txutil, max(total_txutil))
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
    parser = argparse.ArgumentParser(description='Generate node utilization charts from telemetry data')
    parser.add_argument('--nodes', type=str, help='Comma-separated list of node IDs (overrides .env)')
    parser.add_argument('--names', type=str, help='Comma-separated list of node names (must match nodes count)')
    parser.add_argument('--output', type=str, help='Output filename prefix (default: auto-generated)')
    parser.add_argument('--csv', type=str, help='Telemetry CSV file path (overrides .env)')
    
    args = parser.parse_args()
    
    print("Generating node utilization chart...")
    
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
        print("Example: python generate_node_chart.py --nodes '!2df67288,!a0cc8008'")
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
        output_prefix = "multi_node_utilization"
    
    # Create chart
    output_file = create_chart(data, output_prefix)
    
    print(f"\nChart generation complete! Output: {output_file}")
    if args.nodes or args.names or args.csv:
        print("Configuration: Command-line arguments used")
    else:
        print("Configuration loaded from: .env")
    print(f"Telemetry data source: {csv_file}")

if __name__ == "__main__":
    main()
