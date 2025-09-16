#!/bin/bash

echo "🔧 Regenerating clean HTML dashboards..."

# Load environment and dependencies
source "$PWD/common_utils.sh" 2>/dev/null || echo "Warning: common_utils.sh not found"

# Generate clean modern dashboard
echo "📱 Creating modern dashboard..."
python3 -c "
import subprocess
import sys

def create_modern_dashboard():
    html = '''<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>📡 Meshtastic Network Dashboard</title>
    <link href=\"https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css\" rel=\"stylesheet\">
    <!-- Leaflet CSS for GPS Maps -->
    <link rel=\"stylesheet\" href=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.css\" 
          integrity=\"sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=\" crossorigin=\"\" />
    <!-- Leaflet JavaScript -->
    <script src=\"https://unpkg.com/leaflet@1.9.4/dist/leaflet.js\"
            integrity=\"sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=\" crossorigin=\"\"></script>
    <style>
        :root {
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --success-color: #27ae60;
            --warning-color: #f39c12;
            --danger-color: #e74c3c;
            --light-bg: #ecf0f1;
            --dark-bg: #34495e;
            --card-bg: #ffffff;
            --text-primary: #2c3e50;
            --text-secondary: #7f8c8d;
            --border-radius: 12px;
            --shadow: 0 4px 20px rgba(0,0,0,0.1);
            --shadow-hover: 0 8px 30px rgba(0,0,0,0.15);
            --transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", \"Roboto\", \"Oxygen\", \"Ubuntu\", \"Cantarell\", sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: var(--text-primary);
            line-height: 1.6;
            min-height: 100vh;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        .header {
            text-align: center;
            margin-bottom: 30px;
            color: white;
        }

        .header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }

        .header p {
            font-size: 1.1rem;
            opacity: 0.9;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .stat-card {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 25px;
            box-shadow: var(--shadow);
            transition: var(--transition);
            text-align: center;
        }

        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: var(--shadow-hover);
        }

        .stat-card .icon {
            font-size: 2.5rem;
            margin-bottom: 15px;
            color: var(--secondary-color);
        }

        .stat-card .number {
            font-size: 2rem;
            font-weight: bold;
            color: var(--primary-color);
            margin-bottom: 5px;
        }

        .stat-card .label {
            color: var(--text-secondary);
            font-size: 0.9rem;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .section {
            background: var(--card-bg);
            border-radius: var(--border-radius);
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: var(--shadow);
        }

        .section h2 {
            color: var(--primary-color);
            margin-bottom: 20px;
            font-size: 1.5rem;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        #gpsMap {
            height: 500px;
            width: 100%;
            border-radius: 8px;
            border: 1px solid #ddd;
        }

        .map-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }

        .map-stat {
            text-align: center;
            padding: 15px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 8px;
            font-size: 0.9rem;
        }

        .map-stat .number {
            font-size: 1.5rem;
            font-weight: bold;
            display: block;
        }

        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .header h1 {
                font-size: 1.8rem;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"header\">
            <h1>📡 Meshtastic Network Dashboard</h1>
            <p>Real-time monitoring and GPS visualization of your mesh network</p>
        </div>

        <div class=\"stats-grid\">
            <div class=\"stat-card\">
                <div class=\"icon\">🌐</div>
                <div class=\"number\">208</div>
                <div class=\"label\">GPS Nodes</div>
            </div>
            <div class=\"stat-card\">
                <div class=\"icon\">📊</div>
                <div class=\"number\">Active</div>
                <div class=\"label\">Network Status</div>
            </div>
            <div class=\"stat-card\">
                <div class=\"icon\">🔗</div>
                <div class=\"number\">Multi-hop</div>
                <div class=\"label\">Topology</div>
            </div>
            <div class=\"stat-card\">
                <div class=\"icon\">📍</div>
                <div class=\"number\">Germany</div>
                <div class=\"label\">Primary Region</div>
            </div>
        </div>

        <div class=\"section\">
            <h2><i class=\"fas fa-globe\"></i> Network GPS Map</h2>
            
            <div class=\"map-stats\">
                <div class=\"map-stat\">
                    <span class=\"number\">208</span>
                    <span>Nodes with GPS</span>
                </div>
                <div class=\"map-stat\">
                    <span class=\"number\">1</span>
                    <span>Routers</span>
                </div>
                <div class=\"map-stat\">
                    <span class=\"number\">207</span>
                    <span>Clients</span>
                </div>
                <div class=\"map-stat\">
                    <span class=\"number\">1954 km</span>
                    <span>Network Span</span>
                </div>
            </div>
            
            <div id=\"gpsMap\"></div>
        </div>
    </div>
'''

    # Add GPS map data and scripts
    try:
        from gps_map_generator import generate_gps_map_section
        gps_section = generate_gps_map_section()
        # Insert the GPS map JavaScript before closing body tag
        html = html.replace('</div>\\n    </div>', '</div>\\n    </div>\\n' + gps_section)
    except ImportError:
        html += '''
    <script>
        // Simple fallback map if GPS generator not available
        document.addEventListener('DOMContentLoaded', function() {
            const map = L.map('gpsMap').setView([49.0, 8.4], 8);
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
            L.marker([49.0, 8.4]).addTo(map).bindPopup('Network Center');
        });
    </script>
        '''
    
    html += '''
</body>
</html>'''
    
    return html

# Write the modern dashboard
with open('stats-modern-clean.html', 'w') as f:
    f.write(create_modern_dashboard())

print('✅ Clean modern dashboard created as stats-modern-clean.html')
"

# Generate the clean original dashboard using our working script
echo "📄 Creating original dashboard..."
./create_enhanced_stats.sh

echo "✅ Both dashboards regenerated!"
echo "📁 Files created:"
echo "   • stats.html (original style)"
echo "   • stats-modern-clean.html (modern style)"

echo ""
echo "🌐 You can now open these files in a web browser to check if they look better."