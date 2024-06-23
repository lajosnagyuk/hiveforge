Release the Helm chart to install it with the command
```bash

helm package .Helm/hiveforge-controller
hiveforge_controller_chart_version=$(cat .Helm/hiveforge-controller/Chart.yaml | grep version | awk '{print $2}')
helm install --name hiveforge-controller --namespace hiveforge-controller ./hiveforge-controller-${hiveforge_controller_chart_version}.tgz --values ./hiveforge-controller/values.yaml
```
