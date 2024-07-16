#!/bin/bash

# Set variables
#if apikey is not set set it to empty
API_KEY=${1:-""}
AGENT_NAMESPACE="hiveforge-agent"
AGENT_SECRET_NAME="hiveforge-agent-key"

# Check if API_KEY is empty, if so, check for existing secret
if [ -z "$API_KEY" ]; then
    echo "API_KEY is not set. Checking for existing secret..."
    if kubectl get secret -n ${AGENT_NAMESPACE} ${AGENT_SECRET_NAME} &>/dev/null; then
        AGENT_KEY=$(kubectl get secret -n ${AGENT_NAMESPACE} ${AGENT_SECRET_NAME} -o jsonpath='{.data.agentKey}' | base64 --decode)
        if [ -z "$AGENT_KEY" ]; then
            echo "Existing secret found, but it's empty. Please provide an API_KEY. Usage: ./agent-install.sh <API_KEY>"
            exit 1
        else
            echo "Using existing secret."
        fi
    else
        echo "No existing secret found. Please provide an API_KEY. Usage: ./agent-install.sh <API_KEY>"
        exit 1
    fi
else
    echo "API_KEY is set. Creating/updating secret..."
    # this passes in the key to the helm chart which handles the secret creation
    AGENT_KEY=$API_KEY
fi


# Package Helm chart
helm package Helm/hiveforge_agent

# Get chart version
hiveforge_agent_chart_version=$(awk '/version:/ {print $2; exit}' Helm/hiveforge_agent/Chart.yaml)

# Install or upgrade Helm chart
helm upgrade --install hiveforge-agent \
    --namespace ${AGENT_NAMESPACE} \
    --create-namespace \
    hiveforge-agent-${hiveforge_agent_chart_version}.tgz \
    --values values-example.yaml \
    --set hiveforge.agentKey=$AGENT_KEY

# Clean up
rm hiveforge-agent-${hiveforge_agent_chart_version}.tgz
unset API_KEY
unset AGENT_NAMESPACE
unset AGENT_SECRET_NAME

echo "Deployment complete."
