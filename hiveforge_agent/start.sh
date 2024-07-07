#!/bin/bash

# Generate a random UID
RANDOM_UID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# Get the hostname
HOSTNAME=$(hostname)

# Generate a 6-digit hash of the UID
HASH=$(echo $RANDOM_UID | md5sum | cut -c1-6)

# Create the agent ID
AGENT_ID="${HOSTNAME}-${HASH}"

# Export the agent ID as an environment variable
export HIVEFORGE_AGENT_ID=$AGENT_ID

# Derive the agent-specific key
# Note: HIVEFORGE_SHARED_KEY should be set as an environment variable in the container
if [ -z "$HIVEFORGE_SHARED_KEY" ]; then
    echo "Error: HIVEFORGE_SHARED_KEY is not set"
    exit 1
fi

# Use OpenSSL to derive the agent-specific key
AGENT_KEY=$(echo -n "AGENT$AGENT_ID" | openssl dgst -sha256 -hmac "$HIVEFORGE_SHARED_KEY" -binary | base64)

# Export the agent-specific key as an environment variable
export HIVEFORGE_AGENT_KEY=$AGENT_KEY

# Log the agent ID (but not the keys) for debugging purposes
echo "Agent ID: $AGENT_ID"

# Start the Elixir application
exec bin/hiveforge_agent start
