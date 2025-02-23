#!/bin/bash

# install_grafana_dashboards.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: install_grafana_dashboards.sh"
  echo "Interactive demo script that installs Graafana in Kind cluster"
  confirm_step_usage
}

: ${timeout:=5s}
workdir=${1:-kindinstall.tmp}
echo "Working directory $workdir"

mkdir -pv $workdir

toolsdir=$workdir/tools
downloaddir=$workdir/download
mkdir -pv $toolsdir $downloaddir
echo

cmdout=$(curl -s -w "%header{location}" https://github.com/helm/helm/releases/latest)
helm_version=${cmdout##*/}
helm_zipfile=helm-$helm_version-windows-amd64.zip

confirm_step "Download Helm $helm_version" helm_1
curl --output-dir $downloaddir -LO https://get.helm.sh/$helm_zipfile
echo

confirm_step "Extract helm to $toolsdir" helm_2
unzip -j -o -d $toolsdir $downloaddir/$helm_zipfile windows-amd64/helm.exe
echo

ls -l $toolsdir/helm
echo

confirm_step "Show Helm version" helm_3
$toolsdir/helm version
echo

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server
helm repo update >/dev/null
echo

confirm_step "Install kubernetes metrics-server" metrics_1
helm upgrade --install metrics-server metrics-server/metrics-server --namespace kube-system --set args={--kubelet-insecure-tls} 
echo

confirm_step "Show metrics-server service" metrics_2
kubectl get service -A --field-selector metadata.name=metrics-server
echo

confirm_step "Show metrics-server pod" metrics_3
kubectl get pod -A -l app.kubernetes.io/name=metrics-server
echo

confirm_step "Wait till metrics-server is ready" metrics_ready
kubectl wait --timeout $timeout --for condition=Ready pod -l app.kubernetes.io/name=metrics-server -n kube-system
echo

confirm_step "Show node metrics" metrics_4
kubectl top node
echo

confirm_step "Show pod metrics from all namespaces" metrics_5
kubectl top pods -A
echo

confirm_step "Show container metrics from all namespaces" metrics_6
kubectl top pods -A --containers
echo

confirm_step "Show metrics for Kubernetes API server pod" metrics_7
kubectl top pod -n kube-system kube-apiserver-kind-control-plane --containers
echo

helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard
helm repo update >/dev/null
echo

confirm_step "Install kubernetes-dashboard" kbdash_1
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
echo

confirm_step "Create admin-user for kubernetes-dashboard" kbdash_2
kubectl apply -f- <<EOF
# from  https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md

apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF
echo

confirm_step "Show Kubernetes dashboard pods" kbdash_3
kubectl get pods -n kubernetes-dashboard
echo

confirm_step "Show Kubernetes dashboard services" kbdash_4
kubectl get services -n kubernetes-dashboard
echo

confirm_step "Get bearer token for kubernetes-dashboard login" kbdash_5
kubectl -n kubernetes-dashboard create token admin-user
echo

confirm_step "Wait till kubernetes-dashboard is ready" kbdash_ready
kubectl wait --timeout $timeout --for condition=Ready pod --all -n kubernetes-dashboard
echo

confirm_step "Port-forward kubernetes-dashboard to localhost:8443" kbdash_6
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443&
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill kubectl port-forward with \"taskkill -f -pid $winpid\" for script to exit"
fi
echo

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update >/dev/null
echo

confirm_step "Install Prometheus and Grafana" grafana_1
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack --create-namespace --namespace monitoring
echo

confirm_step "Show Grafana and Prometheus pods" grafana_2
kubectl get pods -n monitoring
echo

confirm_step "Show Grafana and Prometheus services" grafana_3
kubectl get services -n monitoring
echo

confirm_step "Wait till Grafana and Prometheus are ready" grafana_ready
kubectl wait --timeout $timeout --for condition=Ready pod --all -n monitoring
echo

confirm_step "Port-forward grafana to localhost:3000, login as admin, password prom-operator" grafana_4
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80&
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill kubectl port-forward with \"taskkill -f -pid $winpid\" for script to exit"
fi
echo

confirm_step "Port-forward prometheus to localhost:9090" grafana_5
kubectl -n monitoring port-forward svc/prometheus-operated 9090&
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill kubectl port-forward with \"taskkill -f -pid $winpid\" for script to exit"
fi
echo

wait

