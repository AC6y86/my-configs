  #!/bin/bash

  echo "=== ADB WiFi Enabler ==="
  echo "Checking for connected Android devices..."

  if ! command -v adb &> /dev/null; then
      echo "Error: ADB is not installed."
      exit 1
  fi

  echo "Debug: Running 'adb devices'..."
  adb_output=$(adb devices)
  echo "Debug: ADB output:"
  echo "$adb_output"

  devices=$(echo "$adb_output" | grep "device$" | grep -v "List
  of devices")
  echo "Debug: Filtered devices:"
  echo "'$devices'"

  if [ -z "$devices" ]; then
      echo "Error: No Android devices found."
      exit 1
  fi

  device_id=$(echo "$devices" | head -n1 | awk '{print $1}')
  echo "Found device: $device_id"

  echo "Enabling ADB over WiFi on port 5555..."
  adb -s "$device_id" tcpip 5555

  sleep 2

  echo "Getting device IP address..."
  ip_address=$(adb -s "$device_id" shell "ip addr show wlan0 |
  grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r\n
  ')

  if [ -z "$ip_address" ]; then
      echo "Warning: Could not detect IP address."
      echo "Check device WiFi settings for IP."
  else
      echo "SUCCESS! Device IP: $ip_address"
      echo "Run: ./connect_adb_wifi.sh $ip_address"
  fi