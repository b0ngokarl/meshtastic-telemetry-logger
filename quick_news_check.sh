#!/bin/bash
# Quick News Check - Run this immediately after changing node roles
# to catch role changes before the automatic system updates the state

echo "🔍 Checking for recent network changes..."
cd /home/jo/meshtastic-telemetry-logger

# Run network news analyzer
python3 network_news_analyzer.py

# Update the stats page with new news
if [[ -f "network_news_embedder.py" && -f "network_news.html" ]]; then
    python3 network_news_embedder.py
    echo "✅ Network news updated in stats.html"
fi

echo "📰 Check stats.html for role changes!"