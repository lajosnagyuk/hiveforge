#!/bin/bash

# Retrieve the master key from Kubernetes secret
MASTER_KEY=$(kubectl get secret hiveforge-controller-master-key -n hiveforge-controller -o jsonpath="{.data.master-key}" | base64 --decode)

# Check if the master key is empty and generate it if necessary
if [ -z "$MASTER_KEY" ]; then
  MASTER_KEY=$(openssl rand -base64 32)
  kubectl create secret generic hiveforge-controller-master-key -n hiveforge-controller --from-literal=master-key=$MASTER_KEY
fi


# Package the Helm chart
helm package Helm/hiveforge_controller

# Extract the chart version from the Chart.yaml
hiveforge_controller_chart_version=$(grep version Helm/hiveforge_controller/Chart.yaml | awk '{print $2}')

# Delete the existing hiveforge-db-setup job
kubectl delete job hiveforge-db-setup -n hiveforge-controller

# Upgrade or install the Helm release
helm upgrade --install hiveforge-controller --namespace hiveforge-controller hiveforge-controller-${hiveforge_controller_chart_version}.tgz --values values-example.yaml \
    --set masterKey=$MASTER_KEY
