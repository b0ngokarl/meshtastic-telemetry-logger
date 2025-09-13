#!/bin/bash

# Migration Helper for Streamlined Meshtastic Telemetry Logger
# This script helps migrate from the old monolithic version to the new modular version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Meshtastic Telemetry Logger - Migration Helper"
echo "=============================================="

# Check if old configuration exists and migrate it
migrate_configuration() {
    echo "Checking for existing configuration..."
    
    # Look for old configuration patterns in the original script
    if [ -f "meshtastic-telemetry-logger.sh" ]; then
        echo "Found original script, extracting configuration..."
        
        # Extract monitored addresses from the original script
        MONITORED_ADDRESSES=$(grep "ADDRESSES=" meshtastic-telemetry-logger.sh | head -1 | sed "s/.*(\(.*\)).*/\1/" | tr "'" '"')
        
        if [ -n "$MONITORED_ADDRESSES" ]; then
            echo "Found monitored addresses: $MONITORED_ADDRESSES"
            
            # Create .env file if it doesn't exist
            if [ ! -f ".env" ]; then
                echo "Creating configuration file..."
                ./config_manager.sh init
                
                # Update with extracted addresses
                if [ -f ".env" ]; then
                    sed -i "s/MONITORED_NODES=.*/MONITORED_NODES=\"$MONITORED_ADDRESSES\"/" .env
                    echo "✅ Configuration migrated successfully"
                fi
            else
                echo "⚠️  Configuration file already exists. Manual review recommended."
            fi
        fi
    fi
}

# Backup existing data files
backup_data() {
    echo "Backing up existing data files..."
    
    for file in telemetry_log.csv nodes_log.csv nodes_log.txt stats.html; do
        if [ -f "$file" ]; then
            backup_file="${file}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$file" "$backup_file"
            echo "✅ Backed up $file to $backup_file"
        fi
    done
}

# Validate the new setup
validate_setup() {
    echo "Validating new setup..."
    
    # Check if all required modules exist
    local required_files=(
        "meshtastic-logger-simple.sh"
        "common_utils.sh"
        "telemetry_collector.sh"
        "html_generator.sh"
        "config_manager.sh"
    )
    
    local missing_files=()
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        echo "✅ All required modules present"
    else
        echo "❌ Missing modules: ${missing_files[*]}"
        return 1
    fi
    
    # Validate configuration
    if ./config_manager.sh validate; then
        echo "✅ Configuration is valid"
    else
        echo "⚠️  Configuration needs attention"
        return 1
    fi
    
    return 0
}

# Show comparison between old and new
show_comparison() {
    echo ""
    echo "Migration Summary"
    echo "================="
    echo ""
    echo "OLD SYSTEM:"
    echo "  • Single monolithic script (2,166 lines)"
    echo "  • Complex configuration embedded in script"
    echo "  • HTML generation mixed with telemetry logic"
    echo "  • Limited error handling"
    echo ""
    echo "NEW STREAMLINED SYSTEM:"
    echo "  • Modular design with separate concerns"
    echo "  • Simple configuration management"
    echo "  • Improved error handling and validation"
    echo "  • Better debugging and maintenance"
    echo ""
    echo "FILES BREAKDOWN:"
    echo "  • meshtastic-logger-simple.sh   - Main orchestrator (176 lines)"
    echo "  • common_utils.sh               - Shared utilities (243 lines)"
    echo "  • telemetry_collector.sh        - Data collection (259 lines)"
    echo "  • html_generator.sh             - Dashboard generation (from original)"
    echo "  • config_manager.sh             - Configuration helper (190 lines)"
    echo ""
    echo "USAGE:"
    echo "  • ./meshtastic-logger-simple.sh        # Continuous collection"
    echo "  • ./meshtastic-logger-simple.sh once   # Single cycle"
    echo "  • ./meshtastic-logger-simple.sh config # Configuration"
    echo "  • ./meshtastic-logger-simple.sh html   # HTML only"
}

# Main migration process
main() {
    echo "Starting migration process..."
    echo ""
    
    # Step 1: Backup existing data
    backup_data
    echo ""
    
    # Step 2: Migrate configuration
    migrate_configuration
    echo ""
    
    # Step 3: Validate new setup
    if validate_setup; then
        echo ""
        echo "🎉 Migration completed successfully!"
        echo ""
        show_comparison
        echo ""
        echo "NEXT STEPS:"
        echo "1. Review configuration: ./config_manager.sh show"
        echo "2. Test the new system: ./meshtastic-logger-simple.sh once"
        echo "3. Start continuous monitoring: ./meshtastic-logger-simple.sh"
        echo ""
        echo "The original script has been preserved for reference."
    else
        echo ""
        echo "❌ Migration encountered issues. Please review the errors above."
        echo "You can manually configure using: ./config_manager.sh"
    fi
}

# Show help if requested
if [[ "${1:-}" == "help" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Migration Helper for Meshtastic Telemetry Logger"
    echo ""
    echo "This script helps migrate from the old monolithic version"
    echo "to the new streamlined modular version."
    echo ""
    echo "Usage: $0"
    echo ""
    echo "The script will:"
    echo "1. Backup your existing data files"
    echo "2. Extract configuration from the old script"
    echo "3. Set up the new modular system"
    echo "4. Validate the new setup"
    exit 0
fi

# Run migration
main