#!/bin/bash

# Filtered logcat monitor script
# Monitors logcat while filtering out spammy/noisy logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTERS_FILE="$SCRIPT_DIR/.logcat_filters"
WHITELIST_FILE="$SCRIPT_DIR/.logcat_whitelist"
SAVE_TO_FILE=""
DISABLE_FILTERS=false
SHOW_COLORS=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -o, --output FILE   Save filtered output to file"
    echo "  -n, --no-filter     Disable all filtering (show raw logcat)"
    echo "  -b, --no-color      Disable color output"
    echo "  -f, --filters FILE  Use custom filters file (default: $FILTERS_FILE)"
    echo "  -w, --whitelist FILE Use custom whitelist file (default: $WHITELIST_FILE)"
    echo ""
    echo "Filters file format:"
    echo "  One grep pattern per line (will be used with 'grep -v')"
    echo "  Lines starting with # are comments"
    echo "  Empty lines are ignored"
    echo ""
    echo "Whitelist file format:"
    echo "  One grep pattern per line (always passes through filters)"
    echo "  Lines starting with # are comments"
    echo "  Empty lines are ignored"
    echo ""
    echo "Examples:"
    echo "  $0                           # Monitor with default filters"
    echo "  $0 -o logcat.txt            # Save filtered output to file"
    echo "  $0 -n                       # Show unfiltered logcat"
    echo "  $0 -f my_filters.txt        # Use custom filters file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -o|--output)
            SAVE_TO_FILE="$2"
            shift 2
            ;;
        -n|--no-filter)
            DISABLE_FILTERS=true
            shift
            ;;
        -b|--no-color)
            SHOW_COLORS=false
            shift
            ;;
        -f|--filters)
            FILTERS_FILE="$2"
            shift 2
            ;;
        -w|--whitelist)
            WHITELIST_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if adb is available
if ! command -v adb &> /dev/null; then
    if [ -x "$SCRIPT_DIR/adb" ]; then
        ADB_CMD="$SCRIPT_DIR/adb"
    else
        echo "Error: ADB not found. Please install Android SDK platform-tools or ensure adb wrapper is available."
        exit 1
    fi
else
    ADB_CMD="adb"
fi

# Check if device is connected
if ! $ADB_CMD devices | grep -q "device[[:space:]]*$"; then
    echo "Error: No Android device connected. Please connect a device and enable USB debugging."
    exit 1
fi

# Create default filters file if it doesn't exist
if [ ! -f "$FILTERS_FILE" ] && [ "$DISABLE_FILTERS" = false ]; then
    echo "Creating default filters file: $FILTERS_FILE"
    cat > "$FILTERS_FILE" << 'EOF'
# Logcat spam filter patterns
# Each line is a grep pattern that will be filtered OUT (using grep -v)
# Lines starting with # are comments

# Compatibility change reporter spam
CompatibilityChangeReporter.*Compat change id reported

# Buffer queue spam
BufferQueueProducer.*dequeueBuffer.*BufferQueue has been abandoned
Adreno.*DequeueBuffer.*dequeueBuffer failed

# Bitrate calculator spam
BitrateCalculator.*accumulate

# VR API performance spam
VrApi.*FPS=.*CPU.*GPU.*MHz

# SLAM anchor spam
Anchor:SlamAnchorMemoryOSSDKClient.*Trying to query head pose too far into the future

# DNS resolver spam
resolv.*res_nmkquery
resolv.*resolv_cache_lookup
resolv.*doQuery.*rcode=

# Activity task manager verbose warnings
ActivityTaskManager.*callingPackage.*has no WPC
ActivityTaskManager.*callingPackage.*is ambiguous

# Core back preview spam
CoreBackPreview.*Setting back callback null

# Telemetry service spam
TelemetryService.*Upload complete callback

# Volumetric window manager spam
VolumetricWindowManagerServiceImpl.*Handling SWMS response

# Activity launch interceptor warnings
ActivityLaunchInterceptorBase.*No activity to handle
EOF
fi

# Build the filter command
build_filter_cmd() {
    if [ "$DISABLE_FILTERS" = true ] || [ ! -f "$FILTERS_FILE" ]; then
        echo "cat"
        return
    fi
    
    local filter_cmd="cat"
    
    # Read filters file and build grep -v chain
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Escape the pattern for grep
        escaped_pattern=$(printf '%s\n' "$line" | sed 's/[[\.*^$()+?{|]/\\&/g')
        filter_cmd="$filter_cmd | grep -v '$line'"
    done < "$FILTERS_FILE"
    
    echo "$filter_cmd"
}

# Color codes for different log levels
setup_colors() {
    if [ "$SHOW_COLORS" = true ]; then
        RED='\033[0;31m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        GREEN='\033[0;32m'
        CYAN='\033[0;36m'
        NC='\033[0m' # No Color
    else
        RED=''
        YELLOW=''
        BLUE=''
        GREEN=''
        CYAN=''
        NC=''
    fi
}

# Apply filters with whitelist protection
apply_filters_with_whitelist() {
    while IFS= read -r logline; do
        # Check if line matches any whitelist pattern (always pass through)
        if [ -f "$WHITELIST_FILE" ]; then
            local whitelisted=false
            while IFS= read -r whitelist_pattern; do
                # Skip empty lines and comments
                if [[ -z "$whitelist_pattern" || "$whitelist_pattern" =~ ^[[:space:]]*# ]]; then
                    continue
                fi
                
                # Check if line matches whitelist pattern (case-insensitive)
                if echo "$logline" | grep -qi "$whitelist_pattern"; then
                    whitelisted=true
                    break
                fi
            done < "$WHITELIST_FILE"
            
            # If whitelisted, always pass through
            if [ "$whitelisted" = true ]; then
                echo "$logline"
                continue
            fi
        fi
        
        # Apply filters to non-whitelisted logs
        local filtered=false
        while IFS= read -r filter_pattern; do
            # Skip empty lines and comments
            if [[ -z "$filter_pattern" || "$filter_pattern" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Check if line matches filter pattern
            if echo "$logline" | grep -q "$filter_pattern"; then
                filtered=true
                break
            fi
        done < "$FILTERS_FILE"
        
        # Output line if it wasn't filtered
        if [ "$filtered" = false ]; then
            echo "$logline"
        fi
    done
}

# Add colors to logcat output
colorize_output() {
    if [ "$SHOW_COLORS" = false ]; then
        cat
        return
    fi
    
    sed \
        -e "s/.*\sE\s.*/$(echo -e "${RED}")&$(echo -e "${NC}")/" \
        -e "s/.*\sW\s.*/$(echo -e "${YELLOW}")&$(echo -e "${NC}")/" \
        -e "s/.*\sI\s.*/$(echo -e "${GREEN}")&$(echo -e "${NC}")/" \
        -e "s/.*\sD\s.*/$(echo -e "${CYAN}")&$(echo -e "${NC}")/" \
        -e "s/.*\sV\s.*/$(echo -e "${BLUE}")&$(echo -e "${NC}")/"
}

# Main execution
main() {
    setup_colors
    
    echo "Starting filtered logcat monitoring..."
    if [ "$DISABLE_FILTERS" = true ]; then
        echo "Filters: DISABLED"
    else
        echo "Filters file: $FILTERS_FILE"
        if [ -f "$FILTERS_FILE" ]; then
            filter_count=$(grep -c -v '^\s*#\|^\s*$' "$FILTERS_FILE" 2>/dev/null || echo "0")
            echo "Active filters: $filter_count"
        fi
        
        echo "Whitelist file: $WHITELIST_FILE"
        if [ -f "$WHITELIST_FILE" ]; then
            whitelist_count=$(grep -c -v '^\s*#\|^\s*$' "$WHITELIST_FILE" 2>/dev/null || echo "0")
            echo "Active whitelist patterns: $whitelist_count"
        fi
    fi
    
    if [ -n "$SAVE_TO_FILE" ]; then
        echo "Output file: $SAVE_TO_FILE"
    fi
    
    echo "Press Ctrl+C to stop..."
    echo "----------------------------------------"
    
    # Build and execute the command pipeline
    if [ "$DISABLE_FILTERS" = true ]; then
        if [ -n "$SAVE_TO_FILE" ]; then
            $ADB_CMD logcat | colorize_output | tee "$SAVE_TO_FILE"
        else
            $ADB_CMD logcat | colorize_output
        fi
    else
        # Build filter chain
        local cmd="$ADB_CMD logcat"
        
        # Apply filters with whitelist protection for spatialvideopoker
        cmd="$cmd | apply_filters_with_whitelist"
        
        # Add colorization and optional file output
        cmd="$cmd | colorize_output"
        if [ -n "$SAVE_TO_FILE" ]; then
            cmd="$cmd | tee '$SAVE_TO_FILE'"
        fi
        
        # Execute the command
        eval "$cmd"
    fi
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n\nLogcat monitoring stopped."; exit 0' INT

# Run main function
main "$@"