#!/usr/bin/env python3
"""
Auto Chart Embedder for Meshtastic Telemetry Dashboard
Embeds generated charts into HTML dashboard after each telemetry collection.
"""

import os
import base64
import re
from pathlib import Path

def embed_charts_in_html():
    """Embed charts into HTML dashboard"""
    html_file = "stats.html"
    chart_files = [
        "multi_node_telemetry_chart.png",
        "multi_node_utilization_chart.png"
    ]
    
    if not os.path.exists(html_file):
        print(f"❌ HTML file {html_file} not found")
        return False
    
    # Read current HTML content
    with open(html_file, 'r', encoding='utf-8') as f:
        html_content = f.read()
    
    # Check if charts section exists
    if '📊 Telemetry Charts' not in html_content:
        print("❌ Charts section not found in HTML")
        return False
    
    charts_html = ""
    
    for chart_file in chart_files:
        if os.path.exists(chart_file):
            print(f"  📊 Embedding {chart_file}")
            
            # Read and encode chart
            with open(chart_file, 'rb') as f:
                chart_data = base64.b64encode(f.read()).decode('utf-8')
            
            # Create chart title
            if "telemetry" in chart_file:
                chart_title = "Multi-Node Telemetry Chart"
            elif "utilization" in chart_file:
                chart_title = "Multi-Node Utilization Chart"
            else:
                chart_title = chart_file.replace('_', ' ').title()
            
            # Add chart HTML
            charts_html += f"""
            <div class="chart-container" style="margin: 20px 0; text-align: center;">
                <h4 style="color: #2c3e50; margin-bottom: 10px;">{chart_title}</h4>
                <img src="data:image/png;base64,{chart_data}" alt="{chart_title}" style="max-width: 100%; height: auto; border: 1px solid #ddd; border-radius: 4px; margin: 10px 0;">
            </div>
            """
        else:
            print(f"  ⚠️  Chart file {chart_file} not found")
    
    if charts_html:
        # Pattern to find charts section and replace content - more specific to avoid duplicates
        pattern = r'(<h3[^>]*>📊 Telemetry Charts</h3>)\s*(<div class="charts-content">.*?</div>)?'
        replacement = f'\\1\n        <div class="charts-content">{charts_html}\n        </div>'
        
        # Replace charts section
        html_content = re.sub(pattern, replacement, html_content, flags=re.DOTALL)
        
        # Write updated HTML
        with open(html_file, 'w', encoding='utf-8') as f:
            f.write(html_content)
        
        print(f"✅ Charts embedded successfully in {html_file}")
        return True
    else:
        print("❌ No charts found to embed")
        return False

if __name__ == "__main__":
    print("🔄 Auto Chart Embedder - Embedding charts in HTML dashboard...")
    success = embed_charts_in_html()
    if success:
        print("✅ Chart embedding complete!")
    else:
        print("❌ Chart embedding failed!")