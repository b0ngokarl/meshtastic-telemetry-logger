# Automated Web Deployment

## Overview

The meshtastic telemetry logger now supports **automated web deployment** that copies all dashboard files to a web server directory after every telemetry collection cycle.

## Features

✅ **Automatic HTML Deployment**: Copies `stats.html` to `index.html` in web directory  
✅ **Chart Deployment**: Copies all PNG and SVG chart files automatically  
✅ **Proper Permissions**: Sets correct ownership and file permissions for web server  
✅ **Configurable Target**: Supports any web server directory path  
✅ **Error Handling**: Graceful failure handling with informative messages  

## Configuration

Edit your `.env` file to configure web deployment:

```bash
# Web Deployment Configuration
WEB_DEPLOY_ENABLED=true       # Enable automatic web deployment after each run (true/false)
WEB_DEPLOY_PATH=/var/www/html # Target directory for web files (default: /var/www/html)
WEB_DEPLOY_OWNER=www-data     # Web server user for file ownership (www-data, apache, nginx, etc.)
```

### Configuration Options

| Setting | Description | Default | Examples |
|---------|-------------|---------|----------|
| `WEB_DEPLOY_ENABLED` | Enable/disable deployment | `true` | `true`, `false` |
| `WEB_DEPLOY_PATH` | Target web directory | `/var/www/html` | `/var/www/html`, `/usr/share/nginx/html`, `/home/user/public_html` |
| `WEB_DEPLOY_OWNER` | Web server user | `www-data` | `www-data`, `apache`, `nginx`, `httpd` |

## Deployment Triggers

Web deployment happens automatically at **two points** in the telemetry collection cycle:

1. **After Initial HTML Generation**: When telemetry data is collected and initial dashboard is created
2. **After Chart Generation**: When charts are generated and embedded in the HTML dashboard

This ensures the web version is always up-to-date with the latest data and charts.

## Files Deployed

The system automatically copies these files to the web directory:

- **`stats.html`** → **`index.html`** (main dashboard)
- **`*.png`** (all PNG chart files)
- **`*.svg`** (all SVG chart files)

## Example Output

When web deployment runs, you'll see output like this:

```
🌐 Deploying to web server: /var/www/html
  ✅ Copied stats.html → /var/www/html/index.html
  📊 Copied multi_node_telemetry_chart.png
  📊 Copied multi_node_utilization_chart.png
  🖼️ Copied multi_node_telemetry_chart.svg
  🖼️ Copied multi_node_utilization_chart.svg
  🔧 Set ownership to www-data
  🔧 Set file permissions to 644
✅ Web deployment complete: 2 PNG, 2 SVG files + HTML
```

## Web Server Requirements

- **Apache**: Default setup works with `/var/www/html`
- **Nginx**: Often uses `/usr/share/nginx/html` or `/var/www/html`
- **Lighttpd**: Typically `/var/www/html` or `/var/www/lighttpd`
- **Other**: Any directory accessible to your web server

## Permissions

The deployment function automatically:
- Creates the target directory if it doesn't exist
- Sets ownership to the configured web server user
- Sets file permissions to `644` (readable by web server)

## Security Notes

- The script uses `sudo` for file operations requiring elevated privileges
- Ensure your user has appropriate sudo permissions for the target directory
- Files are owned by the web server user for security

## Troubleshooting

### Permission Denied Errors
```bash
# Ensure your user can sudo to the web directory
sudo chown -R www-data:www-data /var/www/html
sudo chmod 755 /var/www/html
```

### Different Web Server User
```bash
# For Apache on some systems
WEB_DEPLOY_OWNER=apache

# For Nginx on some systems  
WEB_DEPLOY_OWNER=nginx
```

### Custom Web Directory
```bash
# For user home directories
WEB_DEPLOY_PATH=/home/username/public_html
WEB_DEPLOY_OWNER=username

# For alternative web roots
WEB_DEPLOY_PATH=/usr/share/nginx/html
```

## Disabling Web Deployment

To disable automated web deployment:

```bash
WEB_DEPLOY_ENABLED=false
```

The telemetry logger will continue working normally without web deployment.

## Integration Details

The web deployment feature integrates seamlessly with existing functionality:

- **No Breaking Changes**: Existing configurations continue to work
- **Optional Feature**: Can be disabled without affecting core functionality  
- **Error Tolerant**: Deployment failures don't stop telemetry collection
- **Configurable**: Supports different web server setups

## Access Your Dashboard

After deployment, access your dashboard at:
- **Local**: `http://localhost/`
- **Network**: `http://your-server-ip/`
- **Domain**: `http://your-domain.com/`

The dashboard includes:
- Real-time telemetry data with proper node names
- Interactive charts (PNG embedded, SVG available for download)
- Network statistics and predictions
- Mobile-responsive design