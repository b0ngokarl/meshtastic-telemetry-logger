#!/bin/bash

# Performance-Optimized Dashboard Generator Wrapper
# This script provides a drop-in replacement for slow dashboard generation

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common_utils.sh"
source "$SCRIPT_DIR/html_generator_optimized.sh"

# Main function to generate dashboard with performance optimization
generate_dashboard_optimized() {
    local output_type="${1:-modern}"  # modern, original, or both
    
    debug_log "Starting optimized dashboard generation (type: $output_type)"
    
    # Load configuration
    load_config
    
    # Check if we should use fast mode based on data size
    local telemetry_size=0
    if [ -f "$TELEMETRY_CSV" ]; then
        telemetry_size=$(wc -l < "$TELEMETRY_CSV" 2>/dev/null || echo 0)
    fi
    
    local use_fast_mode="false"
    local max_records="${MAX_DASHBOARD_RECORDS:-1000}"
    
    # Auto-enable fast mode for large datasets
    if [ "$telemetry_size" -gt 2000 ] || [ "${FAST_DASHBOARD_MODE:-false}" = "true" ]; then
        use_fast_mode="true"
        debug_log "Using fast mode due to large dataset ($telemetry_size records)"
    fi
    
    # Set performance environment variables
    export FAST_DASHBOARD_MODE="$use_fast_mode"
    export MAX_DASHBOARD_RECORDS="$max_records"
    export PROGRESSIVE_LOADING="${PROGRESSIVE_LOADING:-true}"
    
    case "$output_type" in
        "modern")
            debug_log "Generating optimized modern dashboard"
            generate_stats_html_modern_optimized "${HTML_OUTPUT_MODERN:-stats-modern.html}"
            ;;
        "original")
            debug_log "Generating optimized original dashboard"
            # For original, use limited data processing
            if [ "$use_fast_mode" = "true" ]; then
                debug_log "Original dashboard generation skipped in fast mode"
                echo "Fast mode enabled - use modern dashboard for better performance" > "${HTML_OUTPUT:-stats.html}"
            else
                # Call original generator with limited scope
                source "$SCRIPT_DIR/html_generator.sh" && generate_stats_html "${HTML_OUTPUT:-stats.html}"
            fi
            ;;
        "both")
            debug_log "Generating both dashboards with optimization"
            generate_dashboard_optimized "modern"
            generate_dashboard_optimized "original"
            ;;
        *)
            echo "Usage: generate_dashboard_optimized [modern|original|both]"
            return 1
            ;;
    esac
    
    debug_log "Dashboard generation completed"
}

# Quick performance test
quick_performance_test() {
    local test_start=$(date +%s)
    
    echo "🚀 Starting performance test..."
    
    # Test optimized generation
    export DEBUG=1
    export MAX_DASHBOARD_RECORDS=500
    export FAST_DASHBOARD_MODE=true
    
    generate_dashboard_optimized "modern"
    
    local test_end=$(date +%s)
    local duration=$((test_end - test_start))
    
    echo "✅ Performance test completed in ${duration} seconds"
    
    if [ -f "stats-modern.html" ]; then
        local file_size=$(wc -c < "stats-modern.html")
        echo "📊 Generated file size: $file_size bytes"
        echo "📈 Dashboard ready for viewing"
    fi
}

# Benchmark comparison between old and new methods
run_performance_benchmark() {
    echo "📊 Running performance benchmark..."
    
    # Test old method (with timeout to prevent hanging)
    echo "Testing original method..."
    local start_time=$(date +%s.%N)
    
    if timeout 30 bash -c 'source html_generator.sh; generate_stats_html_modern stats-old-test.html' 2>/dev/null; then
        local old_time=$(date +%s.%N)
        local old_duration=$(echo "$old_time - $start_time" | bc -l 2>/dev/null || echo "30+")
        echo "✅ Original method: ${old_duration} seconds"
    else
        echo "❌ Original method: Timeout or failed"
        local old_duration="timeout"
    fi
    
    # Test new method
    echo "Testing optimized method..."
    start_time=$(date +%s.%N)
    
    export MAX_DASHBOARD_RECORDS=1000
    export FAST_DASHBOARD_MODE=true
    generate_stats_html_modern_optimized "stats-new-test.html"
    
    local new_time=$(date +%s.%N)
    local new_duration=$(echo "$new_time - $start_time" | bc -l 2>/dev/null || echo "unknown")
    echo "✅ Optimized method: ${new_duration} seconds"
    
    # Compare file sizes
    if [ -f "stats-old-test.html" ] && [ -f "stats-new-test.html" ]; then
        local old_size=$(wc -c < "stats-old-test.html")
        local new_size=$(wc -c < "stats-new-test.html")
        echo "📁 File sizes - Original: $old_size bytes, Optimized: $new_size bytes"
    fi
    
    echo "🏆 Benchmark complete!"
}

# Help function
show_help() {
    cat << EOF
Performance-Optimized Dashboard Generator

Usage:
    $0 [command] [options]

Commands:
    generate [type]     Generate dashboard (modern|original|both)
    test               Run quick performance test
    benchmark          Compare old vs new performance
    help               Show this help message

Environment Variables:
    MAX_DASHBOARD_RECORDS   Maximum records to process (default: 1000)
    FAST_DASHBOARD_MODE     Enable fast processing (true/false)
    PROGRESSIVE_LOADING     Enable progressive loading (true/false)
    DEBUG                   Enable debug output (0/1)

Examples:
    $0 generate modern      # Generate optimized modern dashboard
    $0 test                 # Quick performance test
    $0 benchmark            # Performance comparison

EOF
}

# Main execution
main() {
    case "${1:-generate}" in
        "generate")
            generate_dashboard_optimized "${2:-modern}"
            ;;
        "test")
            quick_performance_test
            ;;
        "benchmark")
            run_performance_benchmark
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi