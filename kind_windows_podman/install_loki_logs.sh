#!/bin/bash

# install_loki_logs.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: install_loki_logs.sh [-d working_directory] [-h] [-l] [-u undo_mode]"
  echo "Interactive demo script that installs Loki in  Kind cluster"
  confirm_step_usage
}

function undo {
  echo "No undo steps defined" 
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

: ${workdir:=kindinstall.tmp}

if $list_steps; then
  confirm_step_list_steps
  exit
fi

# variables needed for both normal and undo modes

toolsdir=$workdir/tools
downloaddir=$workdir/download

echo "Working directory $workdir"

if [[ $mode == undo ]]; then
  undo
  exit
fi

mkdir -pv $workdir
mkdir -pv $toolsdir $downloaddir
echo

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update >/dev/null
echo

confirm_step "Install Loki in simple scalable mode" loki_1
helm upgrade --install -f- loki grafana/loki --create-namespace --namespace loki <<EOF
# from https://grafana.com/docs/loki/latest/setup/install/helm/install-scalable

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1

  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: s3
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  ingester:
    chunk_encoding: snappy
  querier:
    # Default is 4, if you have enough memory and CPU you can increase, reduce if OOMing
    max_concurrent: 4
  pattern_ingester:
    enabled: true
  limits_config:
    allow_structured_metadata: true
    volume_enabled: true

deploymentMode: SimpleScalable

backend:
  replicas: 1
read:
  replicas: 1
write:
  replicas: 1 # To ensure data durability with replication

# Enable minio for storage
minio:
  enabled: true

gateway:
  service:
    type: LoadBalancer
EOF
echo

confirm_step "Show Loki pods" loki_2
kubectl get pods -n loki
echo

confirm_step "Show Loki services" loki_3
kubectl get services -n loki
echo

confirm_step "Port-forward loki to localhost:3100" loki_4
kubectl -n loki port-forward svc/loki-gateway 3100:80&
if [[ -n $! ]]; then
  jobs -l
  ps -W -p $!
  winpid=$(ps -W -p $! | awk 'NR == 2 {print $4}')
  echo "Kill kubectl port-forward with \"taskkill -f -pid $winpid\" for script to exit"
fi
echo

epoch_ns=$(date +%s%N)
confirm_step "Test Loki push API at localhost:3100" loki_5
curl -H Content-Type:application/json http://localhost:3100/loki/api/v1/push --data-raw '{"streams": [{"stream": {"job": "test"}, "values": [["'$epoch_ns'", "fizzbuzz"]]}]}'
echo

confirm_step "Test Loki query_range API at localhost:3100" loki_6
curl -s http://localhost:3100/loki/api/v1/query_range --data-urlencode 'query={job = "test"}' | jq .data.result
echo

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update >/dev/null
echo

confirm_step "Install OpenTelemetry Collector to collect and supply logs to Loki" otel_1
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector -f- --create-namespace --namespace otel <<EOF
# from daemonset values.yaml at https://opentelemetry.io/docs/platforms/kubernetes/getting-started

mode: daemonset

image:
  repository: otel/opentelemetry-collector-k8s

presets:
  # enables the k8sattributesprocessor and adds it to the traces, metrics, and logs pipelines
  kubernetesAttributes:
    enabled: true
  # enables the kubeletstatsreceiver and adds it to the metrics pipelines
  kubeletMetrics:
    enabled: true
  # Enables the filelogreceiver and adds it to the logs pipelines
  logsCollection:
    enabled: true

# send logs to grafana loki otlp endpoint as described at https://grafana.com/docs/loki/latest/send-data/otel
config:
  exporters:
    otlphttp:
      endpoint: http://loki-gateway.loki.svc.cluster.local/otlp
  service:
    pipelines:
      logs:
        exporters: [ otlphttp ]

## The chart only includes the loggingexporter by default
## If you want to send your data somewhere you need to
## configure an exporter, such as the otlpexporter
# config:
#   exporters:
#     otlp:
#       endpoint: "<SOME BACKEND>"
#   service:
#     pipelines:
#       traces:
#         exporters: [ otlp ]
#       metrics:
#         exporters: [ otlp ]
#       logs:
#         exporters: [ otlp ]
EOF
echo

confirm_step "Show opentelemetry pods" otel_2
kubectl get pods -n otel
echo

confirm_step "Show opentelemetry services" otel_3
kubectl get services -n otel
echo

wait

