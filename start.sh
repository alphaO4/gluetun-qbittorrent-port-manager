#!/bin/bash

COOKIES="/tmp/cookies.txt"
CURRENT_PORT=""

# Function to update the qbittorrent port
update_port () {
  PORT=$1

  # Clean up cookies file if it exists
  rm -f "$COOKIES"

  # Log in to the qbittorrent web UI and save cookies
  curl -s -c "$COOKIES" --data "username=$QBITTORRENT_USER&password=$QBITTORRENT_PASS" "${HTTP_S}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/auth/login" > /dev/null
  if [[ $? -ne 0 ]]; then
    echo "Login failed."
    return 1
  fi

  # Update qbittorrent preferences with the new port
  curl -s -b "$COOKIES" --data "json={\"listen_port\": \"$PORT\"}" "${HTTP_S}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/setPreferences" > /dev/null
 # Check current port to see if changes took effect
  CURRENT_PORT=$(curl -s -b $COOKIES ${HTTP_S}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/preferences | jq -r '.listen_port')

  if [ "$CURRENT_PORT" == "$PORT" ]; then
    echo "Successfully updated qbittorrent to port $PORT"
    return 0
  else
    echo "Failed to update port."
    return 1
  fi

  # Clean up cookies file
  rm -f "$COOKIES"

  echo "Successfully updated qbittorrent to port $PORT"
}

# Main loop to check the port and update if necessary
while true; do
  # Follow redirects from gluetun's API (it returns 301 without trailing slash)
  RESPONSE=$(curl -fsSL "${HTTP_S}://${GLUETUN_HOST}:${GLUETUN_PORT}/v1/openvpn/portforwarded" || true)

  # Try to extract the port from JSON first, then fall back to the first integer
  PORT_FORWARDED=$(echo "$RESPONSE" | jq -r '.port // .data.port // .forwarded_port // .portforwarded // empty')
  if [[ -z "$PORT_FORWARDED" ]]; then
    PORT_FORWARDED=$(echo "$RESPONSE" | grep -Eo '[0-9]{2,6}' | head -n1)
  fi

  echo "Received: ${PORT_FORWARDED:-<empty>}"

  # Check if the fetched port is valid
  if [[ -z "$PORT_FORWARDED" || ! "$PORT_FORWARDED" =~ ^[0-9]+$ ]]; then
    echo "Failed to retrieve a valid port number. Response: $RESPONSE"
    sleep 10
    continue
  fi

  # If the current port is different from the forwarded port, update it
  if [[ "$CURRENT_PORT" != "$PORT_FORWARDED" ]]; then
    update_port "$PORT_FORWARDED"
  fi

  # Wait for a specific interval before checking again
  sleep $RECHECK_TIME
done
