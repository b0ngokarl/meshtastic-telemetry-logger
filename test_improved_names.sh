#!/bin/bash

echo "=== Testing Improved Node Name Resolution ==="

# Source the main functions
source ./meshtastic-telemetry-logger.sh

# Enable debug to see the caching process
DEBUG=1

echo "Current node data for !9eed0410:"
grep "9eed0410" nodes_log.csv

echo ""
echo "Testing improved node name resolution..."

# Force reload the cache
NODE_INFO_CACHE_TIMESTAMP=0
load_node_info_cache

echo ""
echo "Getting node info for !9eed0410:"
get_node_info "!9eed0410"

echo ""
echo "Getting node info for a few other nodes:"
get_node_info "!2c9e092b"
get_node_info "!849c4818"

echo ""
echo "=== Test complete ==="