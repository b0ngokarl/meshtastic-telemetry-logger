# data_utils.py

import pandas as pd
import numpy as np
import os
from functools import lru_cache

# Environment-controlled variables for performance tuning
MAX_RECORDS = int(os.environ.get('MAX_DASHBOARD_RECORDS', 1000))
CACHE_ENABLED = os.environ.get('PYTHON_CACHE_ENABLED', 'true').lower() == 'true'

@lru_cache(maxsize=4)
def load_telemetry_data(file_path='telemetry_log.csv'):
    """
    Loads and processes telemetry data from a CSV file with high efficiency.
    - Uses pandas for fast CSV parsing.
    - Caches the result to avoid re-reading the file.
    - Converts data types to memory-efficient formats.
    - Handles large files by reading only the tail if MAX_RECORDS is set.
    """
    if not os.path.exists(file_path):
        return pd.DataFrame()

    try:
        # For large files, read only the last N records to save memory and time
        if MAX_RECORDS > 0:
            # Read the last N lines, which is much faster than reading the whole file
            with open(file_path, 'r') as f:
                lines = f.readlines()
                header = lines[0]
                data_lines = lines[-MAX_RECORDS:]
            
            from io import StringIO
            data = StringIO(header + "".join(data_lines))
            df = pd.read_csv(data)
        else:
            df = pd.read_csv(file_path)

        # --- Data Cleaning and Type Conversion for Performance ---
        # Convert timestamp to datetime objects
        df['timestamp'] = pd.to_datetime(df['timestamp'], errors='coerce')

        # Convert numeric columns, coercing errors to NaN (Not a Number)
        numeric_cols = ['battery', 'voltage', 'channel_util', 'air_util', 'uptime']
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')

        # Optimize memory usage by downcasting numeric types
        for col in df.select_dtypes(include=['float64']).columns:
            df[col] = pd.to_numeric(df[col], downcast='float')
        for col in df.select_dtypes(include=['int64']).columns:
            df[col] = pd.to_numeric(df[col], downcast='integer')

        # Drop rows with invalid timestamp
        df.dropna(subset=['timestamp'], inplace=True)
        
        return df

    except (pd.errors.EmptyDataError, FileNotFoundError):
        return pd.DataFrame()

@lru_cache(maxsize=4)
def load_nodes_data(file_path='nodes_log.csv'):
    """
    Loads and processes node data from a CSV file.
    Caches the result for performance.
    """
    if not os.path.exists(file_path):
        return pd.DataFrame()
    
    try:
        df = pd.read_csv(file_path)
        # Create a mapping from node ID to a friendly name (AKA or LongName)
        df['friendly_name'] = df['AKA'].fillna(df['LongName']).fillna(df['NodeID'])
        return df
    except (pd.errors.EmptyDataError, FileNotFoundError):
        return pd.DataFrame()

def get_node_name_mapping(nodes_df):
    """
    Returns a dictionary mapping node IDs to their friendly names.
    """
    if nodes_df.empty:
        return {}
    return pd.Series(nodes_df.friendly_name.values, index=nodes_df.NodeID).to_dict()

if __name__ == '__main__':
    # Example of how to use the functions and test them
    print("--- Testing Telemetry Data Loader ---")
    telemetry_df = load_telemetry_data()
    if not telemetry_df.empty:
        print(f"Loaded {len(telemetry_df)} telemetry records.")
        print("Data types and memory usage:")
        telemetry_df.info(memory_usage='deep')
    else:
        print("No telemetry data found.")

    print("\n--- Testing Nodes Data Loader ---")
    nodes_df = load_nodes_data()
    if not nodes_df.empty:
        print(f"Loaded {len(nodes_df)} node records.")
        print("Node name mapping:")
        print(get_node_name_mapping(nodes_df))
    else:
        print("No node data found.")
