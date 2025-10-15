
import sys
import json
import re

def parse_meshtastic_output(text):
    """
    Parses the tabular output of 'meshtastic --nodes --show-fields ...'
    and converts it into a JSON object similar to the old '--info --json' format.
    """
    lines = text.splitlines()
    nodes = {}

    # Regex to find the start of a data row (e.g., "| 1 | {'id': ...")
    row_start_re = re.compile(r"^\│\s*\d+\s*│")

    for line in lines:
        if not row_start_re.match(line):
            continue

        parts = [p.strip() for p in line.split('│')[1:-1]]
        if len(parts) < 4:
            continue

        # parts[0] is N, parts[1] is user, parts[2] is deviceMetrics, parts[3] is position
        user_str = parts[1]
        metrics_str = parts[2]
        pos_str = parts[3]

        # --- Process User Data ---
        if user_str == 'N/A':
            continue # Skip nodes with no user data, as we can't get an ID.
        
        # Safely convert Python dict string to JSON string
        user_json_str = user_str.replace("'", '"').replace('False', 'false').replace('True', 'true')
        try:
            user_data = json.loads(user_json_str)
        except json.JSONDecodeError:
            continue # Skip malformed user data

        node_id = user_data.get('id')
        if not node_id:
            continue

        # --- Process Device Metrics ---
        metrics_data = {}
        if metrics_str != 'N/A':
            metrics_json_str = metrics_str.replace("'", '"')
            try:
                metrics_data = json.loads(metrics_json_str)
            except json.JSONDecodeError:
                metrics_data = {} # Ignore malformed metrics

        # --- Process Position Data ---
        pos_data = {}
        if pos_str != 'N/A':
            pos_json_str = pos_str.replace("'", '"')
            try:
                # Handle extended format with lat/lon
                if 'latitude' in pos_json_str and 'longitude' in pos_json_str:
                    # No changes needed for this format
                    pass
                pos_data = json.loads(pos_json_str)
            except json.JSONDecodeError:
                pos_data = {} # Ignore malformed position

        # Combine into a single node object
        nodes[node_id] = {
            "user": user_data,
            "deviceMetrics": metrics_data,
            "position": pos_data
        }

    # Final JSON structure expected by other scripts
    return {"nodes": nodes}

if __name__ == "__main__":
    # Read the entire input from stdin
    stdin_text = sys.stdin.read()
    
    # Parse the text
    parsed_json = parse_meshtastic_output(stdin_text)
    
    # Print the resulting JSON to stdout
    print(json.dumps(parsed_json, indent=4))
