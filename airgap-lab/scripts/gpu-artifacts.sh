#!/usr/bin/env bash
set -euo pipefail
lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory="${AIF_AIRGAP_INVENTORY:-${lab_dir}/generated/inventory.yml}"
sources=()
while IFS= read -r host; do
  sources+=("${lab_dir}/generated/gpu-resources-${host}.json")
done < <(yq -o=json '.' "${inventory}" | jq -r '
  [.all.children.aif_management.hosts, .all.children.aif_workloads.hosts][] |
  to_entries[] | select(.value.airgap_gpu_nodes | length > 0) | .key')
(( ${#sources[@]} > 0 )) || { printf 'No GPU targets in inventory.\n' >&2; exit 2; }
jq -s -f "${lab_dir}/scripts/gpu-images.jq" "${sources[@]}" |
  yq -P '.' > "${lab_dir}/generated/artifacts-gpu.yml"
printf 'Generated the enabled GPU component image set.\n'
