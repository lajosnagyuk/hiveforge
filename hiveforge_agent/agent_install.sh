#!/bin/bash

# Set variables
CONTROLLER_NAMESPACE="hiveforge-controller"
CONTROLLER_SECRET_NAME="hiveforge-controller-master-key"
AGENT_NAMESPACE="hiveforge-agent"
AGENT_SECRET_NAME="hiveforge-agent-shared-key"

# Function to generate shared key
generate_shared_key() {
    local master_key=$1
    echo -n "SHARED_KEY_DERIVATION" | openssl dgst -sha256 -hmac "$master_key" -binary | base64
}

# Retrieve the master key from the controller's secret
MASTER_KEY=$(kubectl get secret -n ${CONTROLLER_NAMESPACE} ${CONTROLLER_SECRET_NAME} -o jsonpath="{.data.master-key}" | base64 --decode)
if [ -z "$MASTER_KEY" ]; then
    echo "Error: Failed to retrieve the master key from the controller secret."
    exit 1
fi

# Check if the shared key secret already exists
if kubectl get secret -n ${AGENT_NAMESPACE} ${AGENT_SECRET_NAME} &> /dev/null; then
    echo "Using existing shared key from secret."
    SHARED_KEY=$(kubectl get secret -n ${AGENT_NAMESPACE} ${AGENT_SECRET_NAME} -o jsonpath="{.data.shared-key}" | base64 --decode)
else
    echo "Generating new shared key."
    SHARED_KEY=$(generate_shared_key "$MASTER_KEY")
fi

# Package Helm chart
helm package Helm/hiveforge_agent

# Get chart version
hiveforge_agent_chart_version=$(cat Helm/hiveforge_agent/Chart.yaml | grep version | awk '{print $2}')

# Install or upgrade Helm chart
helm upgrade --install hiveforge-agent \
    --namespace ${AGENT_NAMESPACE} \
    --create-namespace \
    hiveforge-agent-${hiveforge_agent_chart_version}.tgz \
    --values values-example.yaml \
    --set hiveforge.sharedKey=$SHARED_KEY

# Clean up
unset MASTER_KEY
unset SHARED_KEY

echo "Deployment complete."
