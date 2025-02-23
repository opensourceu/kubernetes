#!/bin/bash

# install_kind_windows.sh

. ${BASH_SOURCE[0]%/*}/util.sh

function usage {
  echo "Usage: install_kind_windows.sh"
  echo "Interactive demo script that installs Kind for local Kubernetes clusters"
  confirm_step_usage
}

function undo {
 
  confirm_step "Uninstall Podman" undo_podman_1
  $downloaddir/podmaninstaller_symlink -uninstall
  echo

  local podmaninstaller_file=$(realpath $downloaddir/podmaninstaller_symlink)
  confirm_step "Delete Podman installer" undo_podman_2 2
  rm -v $podmaninstaller_file
  rm -v $downloaddir/podmaninstaller_symlink
  echo

  confirm_step "Delete kind from $toolsdir" undo_kind
  rm -v $toolsdir/kind
  echo

  confirm_step "Delete kubecolor from $toolsdir" undo_kubecolor
  rm -v $toolsdir/kubecolor
  echo

  confirm_step "Delete kubectl from $toolsdir" undo_kubectl
  rm -v $toolsdir/kubectl
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

toolsdir=$workdir/tools
downloaddir=$workdir/download

echo "Working directory $workdir"
echo

if [[ $mode == undo ]]; then
  undo
  exit
fi
 
mkdir -pv $workdir $toolsdir $downloaddir
echo

kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)

confirm_step "Download kubectl $kubectl_version" kubectl_1
curl --output-dir $downloaddir -LO https://dl.k8s.io/release/$kubectl_version/bin/windows/amd64/kubectl.exe
echo

confirm_step "Copy kubectl to $toolsdir" kubectl_2
cp -v $downloaddir/kubectl $toolsdir
echo

ls -l $toolsdir/kubectl
echo

confirm_step "Show kubectl version" kubectl_3
$toolsdir/kubectl version --client
echo

cmdout=$(curl -Ss -w "%header{location}" https://github.com/kubecolor/kubecolor/releases/latest)
kubecolor_version=${cmdout##*/}
kubecolor_zipfile=kubecolor_${kubecolor_version#v}_windows_amd64.zip

confirm_step "Download kubecolor $kubecolor_version" kubecolor_1
curl --output-dir $downloaddir -LO https://github.com/kubecolor/kubecolor/releases/download/$kubecolor_version/$kubecolor_zipfile
echo

confirm_step "Extract kubecolor to $toolsdir" kubecolor_2
unzip -o -d $toolsdir $downloaddir/$kubecolor_zipfile kubecolor.exe
echo

ls -l $toolsdir/kubecolor
echo

alias kubectl="$toolsdir/kubecolor --force-colors"

confirm_step "Show kubectl version (as kubecolor alias)" kubecolor_3
kubectl version --client
echo

cmdout=$(curl -Ss -w "%header{location}" https://github.com/kubernetes-sigs/kind/releases/latest)
kind_version=${cmdout##*/}

confirm_step "Download kind $kind_version" kind_1
curl --output-dir $downloaddir -LO https://kind.sigs.k8s.io/dl/$kind_version/kind-windows-amd64
echo

confirm_step "Copy kind to $toolsdir" kind_2
cp -v $downloaddir/kind-windows-amd64 $toolsdir/kind.exe
echo

ls -l $toolsdir/kind
echo

confirm_step "Show kind version" kind_3
$toolsdir/kind version
echo

cmdout=$(curl -Ss -w "%header{location}" https://github.com/containers/podman/releases/latest)
podman_version=${cmdout##*/}
podman_installer=podman-${podman_version#v}-setup.exe
podman_installdir=$toolsdir/podman
podman_installdir_winpath=$(cygpath -wa $podman_installdir)

cmdout=
confirm_step "Download Podman $podman_version Windows installer" podman_1
cmdout=$(curl -w "http_response_code %{response_code}\n" --output-dir $downloaddir -LO -z $downloaddir/$podman_installer https://github.com/containers/podman/releases/download/$podman_version/$podman_installer | tee /dev/tty)
echo

if [[ $cmdout == "http_response_code 200" ]]; then
  echo "Update symlink to Podman installer for future uninstall"
  ln -sfv $podman_installer $downloaddir/podmaninstaller_symlink
elif [[ $cmdout == "http_response_code 304" ]]; then
  echo "Podman installer not downloaded because it's same as $downloaddir/$podman_installer"
  [[ -e $downloaddir/podmaninstaller_symlink ]] || ln -sfv $podman_installer $downloaddir/podmaninstaller_symlink
fi

ls -lL $downloaddir/podmaninstaller_symlink
echo

confirm_step "Run Podman installer to install to $podman_installdir" podman_2
$downloaddir/$podman_installer InstallFolder=$podman_installdir_winpath
echo

confirm_step "Show podman version" podman_3
$podman_installdir/podman -v
echo

