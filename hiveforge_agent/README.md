# HiveforgeAgent

# Release and install Helm Charts
```bash
helm package Helm/hiveforge_agent
hiveforge_agent_chart_version=$(cat Helm/hiveforge_agent/Chart.yaml | grep version | awk '{print $2}')
helm upgrade --install hiveforge-agent --namespace hiveforge-agent --create-namespace hiveforge-agent-${hiveforge_agent_chart_version}.tgz --values values-example.yaml

```
