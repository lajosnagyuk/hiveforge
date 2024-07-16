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

# Log the agent ID (but not the keys) for debugging purposes
echo "Agent ID: $AGENT_ID"

# Start the Elixir application
exec bin/hiveforge_agent start
