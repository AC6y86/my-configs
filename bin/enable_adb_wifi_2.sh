#!/bin/bash

# Script to enable ADB over WiFi on connected Android device
# Run this on Machine 1 with the Android device connected via USB

echo "=== ADB WiFi Enabler ==="
echo "Checking for connected Android devices..."

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    echo "Error: ADB is not installed. Please install Android SDK platform-tools."
    exit 1
fi

# Get list of connected devices
devices=$(adb devices | grep -E "device$" | grep -v "List of devices attached")

if [ -z "$devices" ]; then
    echo "Error: No Android devices found. Please connect your device via USB and enable USB debugging."
    exit 1
fi

# Count connected devices
device_count=$(echo "$devices" | wc -l)

if [ "$device_count" -gt 1 ]; then
    echo "Multiple devices found. Using the first device."
fi

# Get first device ID
device_id=$(echo "$devices" | head -n1 | awk '{print $1}')
echo "Found device: $device_id"

# Get device IP address BEFORE switching to TCP mode
echo "Getting device IP address..."

# Get IP address with proper parsing
ip_address=$(adb -s "$device_id" shell "ip addr show wlan0" 2>/dev/null | grep "inet " | grep -v "inet6" | awk '{print $2}' | cut -d'/' -f1 | head -1 | tr -d '\r\n ')

# Enable ADB over TCP/IP on port 5555
echo "Enabling ADB over WiFi on port 5555..."
adb -s "$device_id" tcpip 5555

if [ $? -ne 0 ]; then
    echo "Error: Failed to enable ADB over TCP/IP"
    exit 1
fi

# Wait a moment for the command to take effect
sleep 2

if [ -z "$ip_address" ]; then
    echo "Warning: Could not automatically detect device IP address."
    echo "Please check your device's WiFi settings for the IP address."
    echo ""
    echo "Once you have the IP address, run this command on Machine 2:"
    echo "  ./connect_adb_wifi.sh <DEVICE_IP_ADDRESS>"
else
    echo ""
    echo "SUCCESS! ADB over WiFi is enabled."
    echo ""
    echo "Device IP Address: $ip_address"
    echo ""
    echo "To connect from Machine 2, run:"
    echo "  ./connect_adb_wifi.sh $ip_address"
    echo ""
    echo "You can now disconnect the USB cable."
fi

echo ""
echo "Note: The device will continue to listen on port 5555 until it's restarted."
echo "To disable ADB over WiFi, restart the device or run: adb usb"