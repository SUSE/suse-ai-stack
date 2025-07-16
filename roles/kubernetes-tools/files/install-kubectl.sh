#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "One or more arguments are null or not provided."
  echo "Usage: ${BASH_SOURCE[0]##*/} <IMAGE_ARCH>"
  exit 1
fi


export IMAGE_ARCH=$1
VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)

curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/${IMAGE_ARCH}/kubectl"
curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/${IMAGE_ARCH}/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
