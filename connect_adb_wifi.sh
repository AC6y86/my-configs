#!/bin/bash

# Script to connect to Android device over WiFi
# Run this on Machine 2 to connect to the device enabled on Machine 1

echo "=== ADB WiFi Connector ==="

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo "Error: ADB is not installed. Please install Android SDK platform-tools."
    exit 1
fi

# Check if IP address was provided
if [ $# -eq 0 ]; then
    echo "Error: No IP address provided."
    echo ""
    echo "Usage: $0 <DEVICE_IP_ADDRESS> [PORT]"
    echo "Example: $0 192.168.1.100"
    echo "Example: $0 192.168.1.100 5555"
    echo ""
    echo "Default port is 5555 if not specified."
    exit 1
fi

# Get IP address and port
device_ip="$1"
port="${2:-5555}"

# Validate IP address format (basic check)
if ! [[ "$device_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Error: Invalid IP address format: $device_ip"
    exit 1
fi

# Save current device list
echo "Saving current device list..."
devices_before=$(adb devices | grep -E "device$" | wc -l)

# Disconnect any existing connection to this IP (in case of stale connection)
echo "Cleaning up any existing connections to $device_ip..."
adb disconnect "$device_ip:$port" &> /dev/null

# Connect to the device
echo "Connecting to $device_ip:$port..."
connection_output=$(adb connect "$device_ip:$port" 2>&1)
echo "$connection_output"

# Check if connection was successful
if [[ "$connection_output" == *"connected to"* ]] || [[ "$connection_output" == *"already connected"* ]]; then
    # Give it a moment to establish connection
    sleep 1
    
    # Verify the device is listed
    echo ""
    echo "Verifying connection..."
    if adb devices | grep -q "$device_ip:$port.*device$"; then
        echo "SUCCESS! Connected to device at $device_ip:$port"
        echo ""
        
        # Get device info
        device_info=$(adb -s "$device_ip:$port" shell getprop ro.product.model 2>/dev/null)
        android_version=$(adb -s "$device_ip:$port" shell getprop ro.build.version.release 2>/dev/null)
        
        if [ -n "$device_info" ]; then
            echo "Device Model: $device_info"
            echo "Android Version: $android_version"
        fi
        
        echo ""
        echo "You can now use ADB commands with this device:"
        echo "  adb -s $device_ip:$port <command>"
        echo ""
        echo "Or if it's the only device connected:"
        echo "  adb <command>"
        echo ""
        echo "To disconnect, run:"
        echo "  adb disconnect $device_ip:$port"
        
        # Save connection for easy reconnection
        config_dir="$HOME/.adb_wifi_configs"
        mkdir -p "$config_dir"
        echo "$device_ip:$port" > "$config_dir/last_device"
        echo ""
        echo "Connection saved. To reconnect later, run:"
        echo "  $0 $device_ip $port"
    else
        echo "Error: Connection appeared successful but device is not listed."
        echo "Please check:"
        echo "1. The device has WiFi enabled and is on the same network"
        echo "2. ADB over WiFi is still enabled on the device"
        echo "3. No firewall is blocking port $port"
        exit 1
    fi
else
    echo ""
    echo "Error: Failed to connect to device."
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure the device is on the same network as this machine"
    echo "2. Verify the IP address is correct: $device_ip"
    echo "3. Make sure ADB over WiFi was enabled on the device (port $port)"
    echo "4. Check that no firewall is blocking the connection"
    echo "5. Try pinging the device: ping $device_ip"
    echo ""
    echo "If the device was restarted, you'll need to:"
    echo "1. Connect it via USB to Machine 1"
    echo "2. Run enable_adb_wifi.sh again"
    exit 1
fi