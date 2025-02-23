#!/bin/bash

# create_kind_cluster.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: create_kind_cluster.sh"
  echo "Interactive demo script that creates a Kind cluster"
  confirm_step_usage
}

function undo {
  confirm_step "Remove Kind cluster" undo_kind_1
  kind delete cluster
  echo

  confirm_step "Show Kind cluster" undo_kind_2
  kind get clusters
  echo

  confirm_step "Show Podman containers" undo_kind_3
  podman ps -a
  echo

  confirm_step "Show Podman container images" undo_kind_4
  podman images
  echo
}

while getopts "hlu" opt; do
  case $opt in
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

if $list_steps; then
  confirm_step_list_steps
  exit
fi

if [[ $mode == undo ]]; then
  undo
  exit
fi

confirm_step "Create Kind cluster" kind_1
kind create cluster
echo

confirm_step "Show Kind cluster details" kind_2
kubectl cluster-info --context kind-kind
echo

confirm_step "Show Kind cluster" kind_3
kind get clusters
echo

confirm_step "Show Kubernetes pods" kind_4
kubectl get pods
echo

confirm_step "Show Kubernetes pods in all namespace" kind_5
kubectl get pods -A
echo

confirm_step "Show Kubernetes services in all namespace" kind_6
kubectl get services -A
echo

confirm_step "Show Podman containers" kind_7
podman ps -a
echo

confirm_step "Show Podman container images" kind_8
podman images
echo

