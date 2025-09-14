#!/usr/bin/env python3
"""
Network News Embedder for Meshtastic Telemetry Logger
Embeds generated network news into the HTML dashboard.
"""

import os
import re

def embed_news_in_html(html_file='stats.html', news_file='network_news.html'):
    """Embed network news into HTML dashboard"""
    
    if not os.path.exists(html_file):
        print(f"❌ HTML file not found: {html_file}")
        return False
    
    if not os.path.exists(news_file):
        print(f"❌ News file not found: {news_file}")
        return False
    
    # Read the news HTML
    with open(news_file, 'r', encoding='utf-8') as f:
        news_html = f.read()
    
    # Read the main HTML
    with open(html_file, 'r', encoding='utf-8') as f:
        html_content = f.read()
    
    # Find the news section and replace it
    # Look for the news section pattern
    news_pattern = r'<!-- Network News Section -->(.*?)(?=<h3 id=\'monitored-addresses\')'
    
    if re.search(news_pattern, html_content, re.DOTALL):
        # Replace existing news section
        replacement = f"<!-- Network News Section -->\n{news_html}\n\n"
        html_content = re.sub(news_pattern, replacement, html_content, flags=re.DOTALL)
        print("  📰 Updated existing network news section")
    else:
        # Insert news section before monitored addresses
        monitor_pattern = r'(<h3 id=\'monitored-addresses\'>)'
        if re.search(monitor_pattern, html_content):
            replacement = f"<!-- Network News Section -->\n{news_html}\n\n\\1"
            html_content = re.sub(monitor_pattern, replacement, html_content)
            print("  📰 Inserted new network news section")
        else:
            print("❌ Could not find insertion point for network news")
            return False
    
    # Write the updated HTML
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    return True

def main():
    """Main function"""
    print("🔄 Embedding network news into HTML dashboard...")
    
    if embed_news_in_html():
        print("✅ Network news embedded successfully!")
    else:
        print("❌ Failed to embed network news")

if __name__ == "__main__":
    main()