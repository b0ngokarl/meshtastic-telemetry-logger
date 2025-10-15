#!/usr/bin/env python3

"""
Meshtastic Telemetry Logger - Optional Web Server
Provides HTTP and HTTPS access to the telemetry dashboard and static files.
"""

import os
import sys
import ssl
import http.server
import socketserver
import threading
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse, unquote
import json
import time

class MeshtasticHTTPHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler for serving dashboard and static files."""
    
    def __init__(self, *args, **kwargs):
        # Set the directory to serve files from
        self.directory = str(Path(__file__).parent)
        super().__init__(*args, directory=self.directory, **kwargs)
    
    def do_GET(self):
        """Handle GET requests with custom routing."""
        parsed_path = urlparse(self.path)
        path = unquote(parsed_path.path)
        
        # Route handling
        if path == '/' or path == '/dashboard':
            # Serve main dashboard
            self.serve_dashboard()
        elif path == '/api/status':
            # Simple API endpoint for status
            self.serve_api_status()
        elif path == '/api/refresh':
            # Trigger dashboard refresh
            self.serve_api_refresh()
        elif path.startswith('/static/') or path.endswith(('.html', '.css', '.js', '.json', '.csv', '.png', '.jpg', '.svg')):
            # Serve static files
            super().do_GET()
        else:
            # Default behavior for other requests
            super().do_GET()
    
    def serve_dashboard(self):
        """Serve the main telemetry dashboard."""
        dashboard_file = Path(self.directory) / 'stats-modern.html'
        
        if dashboard_file.exists():
            try:
                with open(dashboard_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()
                self.wfile.write(content.encode('utf-8'))
            except Exception as e:
                self.send_error(500, f"Error serving dashboard: {e}")
        else:
            # Dashboard not found, serve a simple status page
            self.serve_simple_status()
    
    def serve_simple_status(self):
        """Serve a simple status page when dashboard is not available."""
        html_content = """
<!DOCTYPE html>
<html>
<head>
    <title>Meshtastic Telemetry Logger</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; 
               margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; 
                    padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; margin-bottom: 20px; }
        .status { padding: 15px; margin: 10px 0; border-radius: 5px; }
        .info { background: #e8f4fd; border-left: 4px solid #3498db; }
        .warning { background: #fff3cd; border-left: 4px solid #ffc107; }
        pre { background: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
        .refresh-btn { background: #3498db; color: white; padding: 10px 20px; 
                      border: none; border-radius: 5px; cursor: pointer; margin: 10px 5px; }
        .refresh-btn:hover { background: #2980b9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Meshtastic Telemetry Logger Web Server</h1>
        
        <div class="status info">
            <strong>Web Server Status:</strong> Running<br>
            <strong>Time:</strong> {timestamp}<br>
            <strong>Dashboard:</strong> {dashboard_status}
        </div>
        
        <div class="status warning">
            <strong>Note:</strong> Main dashboard (stats-modern.html) not found. 
            Run the telemetry logger to generate dashboard files.
        </div>
        
        <h3>Available Files:</h3>
        <ul>
            {file_list}
        </ul>
        
        <h3>Actions:</h3>
        <button class="refresh-btn" onclick="location.reload()">Refresh Page</button>
        <button class="refresh-btn" onclick="fetch('/api/refresh').then(() => location.reload())">Trigger Dashboard Refresh</button>
        
        <h3>API Endpoints:</h3>
        <ul>
            <li><a href="/api/status">/api/status</a> - Server status JSON</li>
            <li><a href="/api/refresh">/api/refresh</a> - Trigger dashboard refresh</li>
        </ul>
    </div>
</body>
</html>
        """
        
        # List available files
        files = []
        for file_path in Path(self.directory).glob('*.html'):
            files.append(f'<li><a href="/{file_path.name}">{file_path.name}</a></li>')
        for file_path in Path(self.directory).glob('*.csv'):
            files.append(f'<li><a href="/{file_path.name}">{file_path.name}</a></li>')
        
        file_list = '\n'.join(files) if files else '<li>No dashboard files found</li>'
        dashboard_status = "Not Available" if not Path(self.directory, 'stats-modern.html').exists() else "Available"
        
        content = html_content.format(
            timestamp=time.strftime('%Y-%m-%d %H:%M:%S'),
            dashboard_status=dashboard_status,
            file_list=file_list
        )
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(content.encode('utf-8'))
    
    def serve_api_status(self):
        """Serve API status endpoint."""
        status = {
            'server': 'Meshtastic Telemetry Logger Web Server',
            'status': 'running',
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S'),
            'dashboard_available': Path(self.directory, 'stats-modern.html').exists(),
            'files': {
                'html': [f.name for f in Path(self.directory).glob('*.html')],
                'csv': [f.name for f in Path(self.directory).glob('*.csv')],
                'json': [f.name for f in Path(self.directory).glob('*.json')]
            }
        }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(json.dumps(status, indent=2).encode('utf-8'))
    
    def serve_api_refresh(self):
        """Trigger dashboard refresh via HTML generator."""
        try:
            # Try to run the HTML generator script
            result = subprocess.run(['./html_generator.sh'], 
                                  capture_output=True, text=True, timeout=30)
            
            response = {
                'action': 'refresh_dashboard',
                'success': result.returncode == 0,
                'message': 'Dashboard refresh triggered' if result.returncode == 0 else 'Dashboard refresh failed',
                'output': result.stdout if result.returncode == 0 else result.stderr
            }
        except Exception as e:
            response = {
                'action': 'refresh_dashboard',
                'success': False,
                'message': f'Error triggering refresh: {e}',
                'output': ''
            }
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(json.dumps(response, indent=2).encode('utf-8'))
    
    def log_message(self, format, *args):
        """Override log message to include timestamp."""
        sys.stderr.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {format % args}\n")

def generate_self_signed_cert(cert_file, key_file):
    """Generate a self-signed certificate for HTTPS."""
    try:
        # Use openssl command to generate certificate
        subprocess.run([
            'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-keyout', key_file,
            '-out', cert_file, '-days', '365', '-nodes', '-subj',
            '/C=US/ST=State/L=City/O=MeshtasticLogger/OU=Telemetry/CN=localhost'
        ], check=True, capture_output=True)
        
        print(f"✅ Generated self-signed certificate: {cert_file}")
        return True
    except subprocess.CalledProcessError:
        print("❌ Failed to generate certificate with openssl")
        return False
    except FileNotFoundError:
        print("❌ openssl not found. Please install OpenSSL for HTTPS support.")
        return False

def create_simple_cert(cert_file, key_file):
    """Create a simple self-signed certificate using Python's ssl module."""
    try:
        import cryptography
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        import datetime
        
        # Generate private key
        private_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )
        
        # Create certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "State"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "City"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "MeshtasticLogger"),
            x509.NameAttribute(NameOID.COMMON_NAME, "localhost"),
        ])
        
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            private_key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.datetime.utcnow()
        ).not_valid_after(
            datetime.datetime.utcnow() + datetime.timedelta(days=365)
        ).sign(private_key, hashes.SHA256())
        
        # Write certificate and key
        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
        
        with open(key_file, "wb") as f:
            f.write(private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            ))
        
        print(f"✅ Generated self-signed certificate: {cert_file}")
        return True
    except ImportError:
        print("❌ cryptography library not available for certificate generation")
        return False
    except Exception as e:
        print(f"❌ Failed to generate certificate: {e}")
        return False

def start_http_server(port=8080):
    """Start HTTP server."""
    try:
        with socketserver.TCPServer(("", port), MeshtasticHTTPHandler) as httpd:
            print(f"🌐 HTTP Server running on http://localhost:{port}")
            print(f"📊 Dashboard: http://localhost:{port}/dashboard")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 HTTP Server stopped")
    except Exception as e:
        print(f"❌ HTTP Server error: {e}")

def start_https_server(port=8443, cert_file=None, key_file=None):
    """Start HTTPS server."""
    # Default certificate paths
    if cert_file is None:
        cert_file = 'server.crt'
    if key_file is None:
        key_file = 'server.key'
    
    # Generate certificate if it doesn't exist
    if not (Path(cert_file).exists() and Path(key_file).exists()):
        print(f"📜 Certificate files not found, generating self-signed certificate...")
        if not generate_self_signed_cert(cert_file, key_file):
            if not create_simple_cert(cert_file, key_file):
                print("❌ Could not generate SSL certificate. HTTPS server not started.")
                return
    
    try:
        # Create SSL context
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert_file, key_file)
        
        with socketserver.TCPServer(("", port), MeshtasticHTTPHandler) as httpd:
            httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
            print(f"🔒 HTTPS Server running on https://localhost:{port}")
            print(f"📊 Dashboard: https://localhost:{port}/dashboard")
            print(f"⚠️  Using self-signed certificate - browsers will show security warnings")
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 HTTPS Server stopped")
    except Exception as e:
        print(f"❌ HTTPS Server error: {e}")

def load_env_config():
    """Load configuration from .env file."""
    config = {
        'webserver_enabled': True,
        'webserver_port': 8080,
        'webserver_ssl_port': 8443,
        'webserver_ssl_cert': 'server.crt',
        'webserver_ssl_key': 'server.key',
        'webserver_mode': 'both'  # 'http', 'https', or 'both'
    }
    
    env_file = Path('.env')
    if env_file.exists():
        try:
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip().lower()
                        # Remove inline comments and strip quotes
                        value = value.split('#')[0].strip().strip('"\'')
                        
                        if key == 'webserver_enabled':
                            config['webserver_enabled'] = value.lower() in ('true', '1', 'yes', 'on')
                        elif key == 'webserver_port':
                            config['webserver_port'] = int(value)
                        elif key == 'webserver_ssl_port':
                            config['webserver_ssl_port'] = int(value)
                        elif key == 'webserver_ssl_cert':
                            config['webserver_ssl_cert'] = value
                        elif key == 'webserver_ssl_key':
                            config['webserver_ssl_key'] = value
                        elif key == 'webserver_mode':
                            config['webserver_mode'] = value.lower()
        except Exception as e:
            print(f"⚠️  Error reading .env file: {e}")
    
    return config

def main():
    """Main function to start the web server."""
    import argparse
    
    parser = argparse.ArgumentParser(description='Meshtastic Telemetry Logger Web Server')
    parser.add_argument('--port', type=int, default=8080, help='HTTP port (default: 8080)')
    parser.add_argument('--ssl-port', type=int, default=8443, help='HTTPS port (default: 8443)')
    parser.add_argument('--cert', help='SSL certificate file (default: server.crt)')
    parser.add_argument('--key', help='SSL key file (default: server.key)')
    parser.add_argument('--mode', choices=['http', 'https', 'both'], default='both',
                       help='Server mode (default: both)')
    parser.add_argument('--no-ssl', action='store_true', help='Disable HTTPS server')
    
    args = parser.parse_args()
    
    # Load configuration from .env
    config = load_env_config()
    
    # Override with command line arguments
    if not config['webserver_enabled']:
        print("🛑 Web server disabled in configuration")
        return
    
    port = args.port or config['webserver_port']
    ssl_port = args.ssl_port or config['webserver_ssl_port']
    cert_file = args.cert or config['webserver_ssl_cert']
    key_file = args.key or config['webserver_ssl_key']
    mode = args.mode if args.mode != 'both' else config['webserver_mode']
    
    if args.no_ssl:
        mode = 'http'
    
    print("🚀 Starting Meshtastic Telemetry Logger Web Server")
    print(f"📁 Serving files from: {Path(__file__).parent}")
    
    if mode in ['both', 'http']:
        if mode == 'both':
            # Start HTTP server in background thread
            http_thread = threading.Thread(target=start_http_server, args=(port,))
            http_thread.daemon = True
            http_thread.start()
        else:
            start_http_server(port)
    
    if mode in ['both', 'https']:
        start_https_server(ssl_port, cert_file, key_file)

if __name__ == '__main__':
    main()