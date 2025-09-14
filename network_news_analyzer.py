#!/usr/bin/env python3
"""
Network News Analyzer for Meshtastic Telemetry Logger
Analyzes network changes and generates activity news for the dashboard.

Features:
- New nodes discovered
- Lost/offline nodes
- Name changes (AKA changes)
- Public key changes
- Role/mode changes (CLIENT to ROUTER, etc.)
- Configurable time window and hop distance
"""

import csv
import os
import json
from datetime import datetime, timedelta
from typing import Dict, List, Set, Tuple, Optional
import configparser

def load_config():
    """Load configuration from .env file"""
    config = {}
    if os.path.exists('.env'):
        with open('.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove inline comments and quotes
                    value = value.split('#')[0].strip().strip('"').strip("'")
                    config[key.strip()] = value
    
    # Set defaults
    config.setdefault('NEWS_ENABLED', 'true')
    config.setdefault('NEWS_TIME_WINDOW', '24')
    config.setdefault('NEWS_MAX_HOPS', '2')
    config.setdefault('NODES_CSV', 'nodes_log.csv')
    
    return config

def parse_timestamp(timestamp_str: str) -> Optional[datetime]:
    """Parse timestamp from various formats"""
    if not timestamp_str or timestamp_str == 'N/A':
        return None
    
    formats = [
        '%Y-%m-%d %H:%M:%S',
        '%Y-%m-%d %H:%M',
        '%Y-%m-%d',
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(timestamp_str, fmt)
        except ValueError:
            continue
    
    return None

def parse_since_duration(since_str: str) -> Optional[datetime]:
    """Parse 'Since' field like '17 secs ago', '5 mins ago', etc."""
    if not since_str or since_str == 'N/A':
        return None
    
    try:
        parts = since_str.lower().split()
        if len(parts) >= 3 and parts[-1] == 'ago':
            value = int(parts[0])
            unit = parts[1]
            
            now = datetime.now()
            if 'sec' in unit:
                return now - timedelta(seconds=value)
            elif 'min' in unit:
                return now - timedelta(minutes=value)
            elif 'hour' in unit:
                return now - timedelta(hours=value)
            elif 'day' in unit:
                return now - timedelta(days=value)
    except:
        pass
    
    return None

def load_nodes_history(csv_file: str) -> List[Dict]:
    """Load all node data with timestamps"""
    nodes = []
    
    if not os.path.exists(csv_file):
        return nodes
    
    with open(csv_file, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Parse timestamps
            last_heard = parse_timestamp(row.get('LastHeard', ''))
            since_time = parse_since_duration(row.get('Since', ''))
            
            # Use the most recent timestamp available
            timestamp = last_heard or since_time or datetime.now()
            
            nodes.append({
                'user': row.get('User', ''),
                'id': row.get('ID', ''),
                'aka': row.get('AKA', ''),
                'hardware': row.get('Hardware', ''),
                'pubkey': row.get('Pubkey', ''),
                'role': row.get('Role', ''),
                'hops': int(row.get('Hops', 0)) if row.get('Hops', '').isdigit() else 0,
                'timestamp': timestamp,
                'last_heard': row.get('LastHeard', ''),
                'since': row.get('Since', ''),
                'battery': row.get('Battery', ''),
                'channel': int(row.get('Channel', 0)) if row.get('Channel', '').isdigit() else 0,
            })
    
    return nodes

def load_previous_state(state_file: str = 'network_state.json') -> Dict:
    """Load previous network state for comparison"""
    if os.path.exists(state_file):
        try:
            with open(state_file, 'r') as f:
                return json.load(f)
        except:
            pass
    return {}

def save_current_state(nodes: List[Dict], state_file: str = 'network_state.json'):
    """Save current network state for future comparison"""
    state = {}
    for node in nodes:
        if node['id']:
            state[node['id']] = {
                'user': node['user'],
                'aka': node['aka'],
                'hardware': node['hardware'],
                'pubkey': node['pubkey'],
                'role': node['role'],
                'hops': node['hops'],
                'timestamp': node['timestamp'].isoformat() if node['timestamp'] else None,
                'battery': node['battery'],
                'channel': node['channel'],
            }
    
    with open(state_file, 'w') as f:
        json.dump(state, f, indent=2)

def filter_by_time_and_hops(nodes: List[Dict], time_window_hours: int, max_hops: int) -> List[Dict]:
    """Filter nodes by time window and hop distance"""
    cutoff_time = datetime.now() - timedelta(hours=time_window_hours)
    
    filtered = []
    for node in nodes:
        # Filter by time (if we have a timestamp)
        if node['timestamp'] and node['timestamp'] < cutoff_time:
            continue
        
        # Filter by hops
        if node['hops'] > max_hops:
            continue
        
        filtered.append(node)
    
    return filtered

def analyze_network_changes(current_nodes: List[Dict], previous_state: Dict, time_window_hours: int, max_hops: int) -> Dict:
    """Analyze network changes and generate news"""
    news = {
        'new_nodes': [],
        'lost_nodes': [],
        'name_changes': [],
        'pubkey_changes': [],
        'role_changes': [],
        'hardware_changes': [],
        'stats': {
            'total_active_nodes': 0,
            'new_count': 0,
            'lost_count': 0,
            'changed_count': 0
        }
    }
    
    # Filter current nodes by time and hops
    filtered_nodes = filter_by_time_and_hops(current_nodes, time_window_hours, max_hops)
    current_ids = {node['id'] for node in filtered_nodes if node['id']}
    previous_ids = set(previous_state.keys())
    
    news['stats']['total_active_nodes'] = len(current_ids)
    
    # Find new nodes
    new_ids = current_ids - previous_ids
    for node in filtered_nodes:
        if node['id'] in new_ids and node['id']:
            news['new_nodes'].append({
                'id': node['id'],
                'user': node['user'],
                'aka': node['aka'],
                'hardware': node['hardware'],
                'role': node['role'],
                'hops': node['hops'],
                'timestamp': node['timestamp'].strftime('%Y-%m-%d %H:%M') if node['timestamp'] else 'Unknown'
            })
    
    news['stats']['new_count'] = len(news['new_nodes'])
    
    # Find lost nodes (in previous but not in current)
    lost_ids = previous_ids - current_ids
    for node_id in lost_ids:
        if node_id in previous_state:
            prev_node = previous_state[node_id]
            news['lost_nodes'].append({
                'id': node_id,
                'user': prev_node.get('user', ''),
                'aka': prev_node.get('aka', ''),
                'hardware': prev_node.get('hardware', ''),
                'hops': prev_node.get('hops', 0)
            })
    
    news['stats']['lost_count'] = len(news['lost_nodes'])
    
    # Find changes in existing nodes
    for node in filtered_nodes:
        if not node['id'] or node['id'] not in previous_state:
            continue
        
        prev_node = previous_state[node['id']]
        changes = []
        
        # Check name changes (AKA or User)
        if (node['aka'] != prev_node.get('aka', '') and node['aka'] and prev_node.get('aka', '')) or \
           (node['user'] != prev_node.get('user', '') and node['user'] and prev_node.get('user', '')):
            news['name_changes'].append({
                'id': node['id'],
                'old_name': prev_node.get('aka', '') or prev_node.get('user', ''),
                'new_name': node['aka'] or node['user'],
                'hops': node['hops']
            })
            changes.append('name')
        
        # Check public key changes
        if node['pubkey'] != prev_node.get('pubkey', '') and node['pubkey'] and node['pubkey'] != 'N/A':
            news['pubkey_changes'].append({
                'id': node['id'],
                'name': node['aka'] or node['user'],
                'old_pubkey': prev_node.get('pubkey', '')[:16] + '...' if prev_node.get('pubkey', '') else 'None',
                'new_pubkey': node['pubkey'][:16] + '...' if len(node['pubkey']) > 16 else node['pubkey'],
                'hops': node['hops']
            })
            changes.append('pubkey')
        
        # Check role changes
        if node['role'] != prev_node.get('role', '') and node['role'] and node['role'] != 'N/A':
            news['role_changes'].append({
                'id': node['id'],
                'name': node['aka'] or node['user'],
                'old_role': prev_node.get('role', 'Unknown'),
                'new_role': node['role'],
                'hops': node['hops']
            })
            changes.append('role')
        
        # Check hardware changes
        if node['hardware'] != prev_node.get('hardware', '') and node['hardware'] and node['hardware'] != 'N/A':
            news['hardware_changes'].append({
                'id': node['id'],
                'name': node['aka'] or node['user'],
                'old_hardware': prev_node.get('hardware', 'Unknown'),
                'new_hardware': node['hardware'],
                'hops': node['hops']
            })
            changes.append('hardware')
        
        if changes:
            news['stats']['changed_count'] += 1
    
    return news

def format_news_html(news: Dict, time_window_hours: int, max_hops: int) -> str:
    """Format news as HTML"""
    html = []
    
    # Header
    html.append(f"<h3 id='network-news'>📰 Network Activity (Last {time_window_hours}h, ≤{max_hops} hops)</h3>")
    html.append("<div class='news-content'>")
    
    # Summary stats
    stats = news['stats']
    html.append(f"<div class='news-summary'>")
    html.append(f"<p><strong>Active nodes:</strong> {stats['total_active_nodes']} | ")
    html.append(f"<span style='color: #28a745;'>New: {stats['new_count']}</span> | ")
    html.append(f"<span style='color: #dc3545;'>Lost: {stats['lost_count']}</span> | ")
    html.append(f"<span style='color: #007bff;'>Changed: {stats['changed_count']}</span></p>")
    html.append("</div>")
    
    # Check if there's any news
    has_news = any([
        news['new_nodes'],
        news['lost_nodes'], 
        news['name_changes'],
        news['pubkey_changes'],
        news['role_changes'],
        news['hardware_changes']
    ])
    
    if not has_news:
        html.append("<p style='color: #6c757d; font-style: italic;'>No significant network changes detected.</p>")
    else:
        # New nodes
        if news['new_nodes']:
            html.append("<h4 style='color: #28a745; margin-top: 20px;'>🆕 New Nodes</h4>")
            html.append("<ul>")
            for node in news['new_nodes']:
                name = node['aka'] or node['user'] or 'Unknown'
                html.append(f"<li><strong>{node['id']}</strong> ({name}) - {node['hardware']} - {node['hops']} hops - <em>{node['timestamp']}</em></li>")
            html.append("</ul>")
        
        # Lost nodes
        if news['lost_nodes']:
            html.append("<h4 style='color: #dc3545; margin-top: 20px;'>📵 Lost Nodes</h4>")
            html.append("<ul>")
            for node in news['lost_nodes']:
                name = node['aka'] or node['user'] or 'Unknown'
                html.append(f"<li><strong>{node['id']}</strong> ({name}) - {node['hardware']} - was {node['hops']} hops</li>")
            html.append("</ul>")
        
        # Name changes
        if news['name_changes']:
            html.append("<h4 style='color: #007bff; margin-top: 20px;'>🏷️ Name Changes</h4>")
            html.append("<ul>")
            for change in news['name_changes']:
                html.append(f"<li><strong>{change['id']}</strong> renamed from '{change['old_name']}' to '{change['new_name']}' ({change['hops']} hops)</li>")
            html.append("</ul>")
        
        # Role changes
        if news['role_changes']:
            html.append("<h4 style='color: #fd7e14; margin-top: 20px;'>⚙️ Role Changes</h4>")
            html.append("<ul>")
            for change in news['role_changes']:
                html.append(f"<li><strong>{change['name']}</strong> ({change['id']}) changed from {change['old_role']} to {change['new_role']} ({change['hops']} hops)</li>")
            html.append("</ul>")
        
        # Hardware changes
        if news['hardware_changes']:
            html.append("<h4 style='color: #6f42c1; margin-top: 20px;'>🔧 Hardware Changes</h4>")
            html.append("<ul>")
            for change in news['hardware_changes']:
                html.append(f"<li><strong>{change['name']}</strong> ({change['id']}) changed from {change['old_hardware']} to {change['new_hardware']} ({change['hops']} hops)</li>")
            html.append("</ul>")
        
        # Public key changes
        if news['pubkey_changes']:
            html.append("<h4 style='color: #e83e8c; margin-top: 20px;'>🔐 Public Key Changes</h4>")
            html.append("<ul>")
            for change in news['pubkey_changes']:
                html.append(f"<li><strong>{change['name']}</strong> ({change['id']}) updated public key ({change['hops']} hops)</li>")
            html.append("</ul>")
    
    html.append("</div>")
    
    return '\n'.join(html)

def main():
    """Main function"""
    config = load_config()
    
    # Check if news is enabled
    if config.get('NEWS_ENABLED', 'true').lower() != 'true':
        print("📰 Network news is disabled in configuration")
        return
    
    time_window = int(config.get('NEWS_TIME_WINDOW', 24))
    max_hops = int(config.get('NEWS_MAX_HOPS', 2))
    nodes_csv = config.get('NODES_CSV', 'nodes_log.csv')
    
    print(f"📰 Analyzing network activity (last {time_window}h, ≤{max_hops} hops)...")
    
    # Load current nodes data
    current_nodes = load_nodes_history(nodes_csv)
    if not current_nodes:
        print(f"❌ No nodes data found in {nodes_csv}")
        return
    
    # Load previous state
    previous_state = load_previous_state()
    
    # Analyze changes
    news = analyze_network_changes(current_nodes, previous_state, time_window, max_hops)
    
    # Generate HTML
    news_html = format_news_html(news, time_window, max_hops)
    
    # Save news to file
    with open('network_news.html', 'w') as f:
        f.write(news_html)
    
    # Save current state for next comparison
    save_current_state(current_nodes)
    
    # Print summary
    stats = news['stats']
    print(f"✅ Network news generated:")
    print(f"   Active nodes: {stats['total_active_nodes']}")
    print(f"   New: {stats['new_count']}, Lost: {stats['lost_count']}, Changed: {stats['changed_count']}")
    print(f"   News saved to: network_news.html")

if __name__ == "__main__":
    main()