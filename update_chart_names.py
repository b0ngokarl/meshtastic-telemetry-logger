#!/usr/bin/env python3
"""
Utility script to automatically generate CHART_NODE_NAMES from nodes_log.csv
This script reads the current CHART_NODES from .env and looks up the corresponding
node names from the nodes_log.csv file, then updates the .env file.
"""

import csv
import os
import re


def load_env_file(env_file='.env'):
    """Load environment variables from .env file"""
    config = {}
    if os.path.exists(env_file):
        with open(env_file, 'r') as file:
            for line in file:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip().strip('"\'')
                    config[key] = value
    return config


def get_node_names_from_csv(chart_nodes, csv_file='nodes_log.csv'):
    """Extract node names from nodes_log.csv for the given node IDs"""
    node_names = {}
    
    if not os.path.exists(csv_file):
        print(f"Warning: {csv_file} not found")
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
        print(f"Error reading {csv_file}: {e}")
    
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


def main():
    """Main function to update chart node names automatically"""
    print("Updating CHART_NODE_NAMES automatically from nodes_log.csv...")
    
    # Load current configuration
    config = load_env_file()
    chart_nodes_str = config.get('CHART_NODES', '')
    
    if not chart_nodes_str:
        print("Error: No CHART_NODES found in .env file")
        return
    
    # Parse chart nodes
    chart_nodes = [node.strip() for node in chart_nodes_str.split(',') if node.strip()]
    
    if not chart_nodes:
        print("Error: CHART_NODES is empty")
        return
    
    print(f"Found {len(chart_nodes)} nodes in CHART_NODES:")
    for node in chart_nodes:
        print(f"  {node}")
    
    # Get node names from CSV
    node_names = get_node_names_from_csv(chart_nodes)
    
    print(f"\nFound names for {len(node_names)} nodes:")
    for node_id, name in node_names.items():
        print(f"  {node_id}: {name}")
    
    # Update .env file
    if update_env_file(chart_nodes, node_names):
        print(f"\n✅ Successfully updated CHART_NODE_NAMES in .env file")
        
        # Show the new configuration
        updated_config = load_env_file()
        print(f"\nNew CHART_NODE_NAMES:")
        print(f'"{updated_config.get("CHART_NODE_NAMES", "")}"')
    else:
        print("\n❌ Failed to update .env file")


if __name__ == "__main__":
    main()
