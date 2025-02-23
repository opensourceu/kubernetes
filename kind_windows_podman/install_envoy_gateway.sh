#!/bin/bash

# install_envoy_gateway.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: install_envoy_gateway.sh [-d working_directory] [-h] [-l] [-u undo_mode]"
  echo "Interactive demo script that installs Envoy Gateway in Kind cluster"
  confirm_step_usage
}

function undo {
  confirm_step "Uninstall Envoy gateway quickstart example" undo_envoy_1
  kubectl delete -f $envoy_gateway_quickstart_manifest_file -n default
  echo

  confirm_step "Uninstall Envoy gateway" undo_envoy_2
  helm delete $envoy_gateway_rollout -n envoy-gateway-system
  echo

  confirm_step "Delete cloud-provider-kind from $toolsdir" undo_provider
  rm -v $toolsdir/cloud-provider-kind
  echo

  confirm_step "Uninstall hello-app from Kind cluster" undo_hello_1
  kubectl delete all --all -n hello
  echo

  confirm_step "Delete hello-app image from Kind node container" undo_hello_2
  podman exec -it kind-control-plane crictl rmi localhost/hello-app:localhello
  echo

  local hello_image_id=$(podman images hello-app --noheading --format "table {{.ID}}")

  confirm_step "Delete hello-app image ID $hello_image_id from Podman machine" undo_hello_3
  podman image rm $hello_image_id
  echo
}

while getopts "d:hlu" opt; do
  case $opt in
    d)
      workdir=$OPTARG
      ;;
    l)
      list_steps=true
      ;;
    u)
      mode=undo
      ;;
    h) usage; exit 0
      ;;
    *) usage; exit 1
  esac
done
shift $((OPTIND - 1))

if (($# > 0)); then
  usage
  exit 1
fi

: ${mode:=normal}
: ${list_steps:=false}
: ${workdir:=kindinstall.tmp}

if $list_steps; then
  confirm_step_list_steps
  exit
fi

# variables needed for both normal and undo modes

toolsdir=$workdir/tools
downloaddir=$workdir/download

envoy_gateway_rollout=eg
envoy_gateway_dir=$downloaddir/envoy_gateway
envoy_gateway_quickstart_manifest_file=$envoy_gateway_dir/quickstart.yaml


echo "Working directory $workdir"
echo

if [[ $mode == undo ]]; then
  undo
  exit
fi

mkdir -pv $workdir $toolsdir $downloaddir
echo

gkesamples_dir=$workdir/kubernetes-engine-samples
confirm_step "Clone GKE hello-app repo" hello_1
git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples $gkesamples_dir
echo

hello_dir=$gkesamples_dir/quickstarts/hello-app
ls -ld $hello_dir
echo

confirm_step "Build hello-app container image on Podman machine" hello_2
podman build --format docker --squash-all -t hello-app:localhello $hello_dir
echo

confirm_step "Show hello-app image on Podman machine" hello_3
podman images hello-app
echo

hello_tarfile=$workdir/hello-app.tar

confirm_step "Export hello-app image as tarfile to load into Kind cluster container" hello_4
podman save --format docker-archive -o $hello_tarfile hello-app:localhello
echo

ls -l $hello_tarfile
echo

confirm_step "Load hello-app image tarfile into Kind cluster container" hello_5
kind load image-archive $hello_tarfile
echo

confirm_step "Show hello-app image in Kind container" hello_6
podman exec -i kind-control-plane crictl images | grep -E "IMAGE|hello-app"
echo

confirm_step "Deploy hello-app in hello namespace in Kind cluster" hello_7
kubectl apply -f- <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: hello
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/name: hello-app
  name: hello-app
  namespace: hello
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: hello-app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: hello-app
    spec:
      containers:
      - image: localhost/hello-app:localhello
        name: hello-app
        ports:
        - containerPort: 8080
EOF
echo

confirm_step "Show hello-app pod" hello_8
kubectl get pods -n hello
echo

confirm_step "Create helloservice load balancer service for hello-app" hello_9
kubectl expose deployment hello-app --type LoadBalancer --name helloservice -n hello
echo

confirm_step "Show helloservice service" hello_10
kubectl get services -n hello
echo

confirm_step "Port-forward helloservice to localhost:8080" hello_11
kubectl -n hello port-forward svc/helloservice 8080&
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill kubectl port-forward with \"taskkill -f -pid $winpid\" for script to exit"
fi
echo

confirm_step "Test helloservice with curl on localhost:8080" hello_12
curl localhost:8080
echo

cmdout=$(curl -s -w "%header{location}" https://github.com/kubernetes-sigs/cloud-provider-kind/releases/latest)
kindlb_version=${cmdout##*/}
kindlb_tarfile=cloud-provider-kind_${kindlb_version#v}_windows_amd64.tar.gz

confirm_step "Download Kind cloud provider $kindlb_version" provider_1
curl --output-dir $downloaddir -LO https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/$kindlb_version/$kindlb_tarfile
echo

confirm_step "Extract cloud-provider-kind to $toolsdir" provider_2
tar -C $toolsdir -xvf $downloaddir/$kindlb_tarfile cloud-provider-kind.exe
echo

ls -l $toolsdir/cloud-provider-kind
echo

confirm_step "Show Kind provider version" provider_3
$toolsdir/cloud-provider-kind list-images
echo

confirm_step "Show Podman machine inotify settings" provider_4
podman machine ssh sysctl -a 2>/dev/null | grep inotify
echo

echo "You may need to increase inotify limits on the Podman machine. For example, fs.inotify.max_user_instances = 128 is too low for a Kind cluster to properly operate. Change settings with \"sudo sysctl -w fs.inotify.max_user_instances=8192 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p\""
echo

confirm_step "Show all load balancer services with pending external IPs" provider_5
kubectl get services -A --field-selector spec.type=LoadBalancer
echo

provider_logsdir=$workdir/provider_logs
mkdir -p $provider_logsdir

confirm_step "Run Kind cloud provider as admin, logs in $provider_logsdir" provider_6
sudo --inline $toolsdir/cloud-provider-kind -enable-log-dumping -logs-dir $provider_logsdir >$provider_logsdir/cloud-provider-kind.log 2>&1 &
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill cloud-provider-kind with \"sudo --inline taskkill -f -pid $winpid\" for script to exit"
fi
echo

confirm_step "Show all load balancer services with external IPs asssigned" provider_7
kubectl get services -A --field-selector spec.type=LoadBalancer
echo

cmdout=$(curl -Ss -w "%header{location}" https://github.com/envoyproxy/gateway/releases/latest)
envoygateway_version=${cmdout##*/}

confirm_step "Install Envoy gateway version $envoygateway_version" envoy_1
helm upgrade --install $envoy_gateway_rollout oci://docker.io/envoyproxy/gateway-helm --version $envoygateway_version -n envoy-gateway-system --create-namespace
echo

confirm_step "Show Envoy Gateway pods" envoy_2
kubectl get pods -n envoy-gateway-system
echo

confirm_step "Show Envoy gateway services" envoy_3
kubectl get services -n envoy-gateway-system
echo

# save quickstart manifest for undo mode
envoy_gateway_quickstart_manifest=https://github.com/envoyproxy/gateway/releases/download/$envoygateway_version/quickstart.yaml
cmdout=$(curl --no-progress-meter -w "%{response_code}" -L --create-dirs -o $envoy_gateway_quickstart_manifest_file -z $envoy_gateway_quickstart_manifest_file $envoy_gateway_quickstart_manifest | tee /dev/tty)
if (( $cmdout == 304 )); then
  echo "Skip download Envoy gateway quickstart manifest because it's not newer than $envoy_gateway_quickstart_manifest_file"
elif (( $cmdout == 200 )); then
  echo "Download newer Envoy gateway quickstart manifest to $envoy_gateway_quickstart_manifest_file"
else
  echo >&2 "Unexpected output from curl $envoy_gateway_quickstart_manifest \"$cmdout\""
fi
echo

confirm_step "Install Envoy gateway quickstart example" envoy_4
kubectl apply -f $envoy_gateway_quickstart_manifest -n default
echo

confirm_step "Show Envoy Gateway CRDs" envoy_5
kubectl get crds --plain -o json |
jq -r '
  .items[] |
  select(.spec.group == "gateway.envoyproxy.io" or .spec.group == "gateway.networking.k8s.io") |
  [.metadata.name, .spec.group, .metadata.creationTimestamp] |
  @tsv
' |
sort -k2,2 -k1,1 -k3,3 |
column -t -o "    " -N "Name,API Group,Created At"
echo

confirm_step "Show Envoy quickstart example pods" envoy_6
kubectl get pods -n default
echo

confirm_step "Show Envoy quickstart example services" envoy_7
kubectl get services -n default
echo

confirm_step "Show all gateways" envoy_8
kubectl get gateways -A
echo

gateway_ip=$(kubectl get gateway/eg -o jsonpath="{.status.addresses[0].value}")

confirm_step "Send request to Envoy example app through gateway IP $gateway_ip" envoy_9
curl -v -H Host:www.example.com http://$gateway_ip/get
echo


wait

