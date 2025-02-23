#!/bin/bash

# create_podman_machine.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: create_podman_machine.sh"
  echo "Interactive demo script to create a Podman machine"
  confirm_step_usage
}

function undo {
  confirm_step "Stop Podman machine" undo_podman_1
  podman machine stop
  echo

  confirm_step "Show Podman machine" undo_podman_2
  podman machine ls
  echo

  confirm_step "Remove Podman machine" undo_podman_3
  podman machine rm podman-machine-default
  echo

  confirm_step "Show Podman machine" undo_podman_4
  podman machine ls
  echo

  confirm_step "Show WSL distros" undo_podman_5
  wsl --list --verbose
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

confirm_step "Create Podman machine" podman_1
podman machine init
echo

confirm_step "Show Podman machine" podman_2
podman machine ls
echo

confirm_step "Start Podman machine" podman_3
podman machine start
echo

confirm_step "Show Podman machine" podman_4
podman machine ls
echo

confirm_step "Show Podman machine details" podman_5
podman machine info
echo

confirm_step "Show WSL distros" podman_6
wsl --list --verbose
echo

confirm_step "Show Podman machine uname" podman_7
wsl -d podman-machine-default uname -a
echo

confirm_step "Show Podman machine Redhat release" podman_8
wsl -d podman-machine-default cat /etc/redhat-release
echo

confirm_step "Verify cgroup version v2 in Podman machine" podman_9
podman info | grep -i cgroupversion
echo

echo "If Podman machine is not using cgroupv2, set \"kernelCommandLine = cgroup_no_v1=all\" in WSL .wslconfig file to disable cgroupv1 and restart WSL"
echo "See https://manned.org/man/cgroups and https://github.com/microsoft/WSL/issues/10050 for more info"
echo

