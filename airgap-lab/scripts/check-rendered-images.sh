#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
manifest="${lab_dir}/artifacts.yml"

usage() {
  printf '%s\n' \
    "Usage: $0 [--manifest FILE] RENDERED-MANIFEST.yaml [...]" \
    "Fails when a literal image in rendered Kubernetes YAML is absent from the artifact set."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[[ $# -gt 0 ]] || { usage >&2; exit 2; }
[[ -f "${manifest}" ]] || { printf 'Manifest not found: %s\n' "${manifest}" >&2; exit 2; }
command -v yq >/dev/null || { printf 'Required command not found: yq\n' >&2; exit 2; }

normalize_image() {
  local image=$1 first remainder
  image="${image#docker://}"
  first="${image%%/*}"
  if [[ "${image}" != */* ]]; then
    printf 'docker.io/library/%s\n' "${image}"
  elif [[ "${first}" == *.* || "${first}" == *:* || "${first}" == "localhost" ]]; then
    remainder="${image#*/}"
    if [[ "${first}" == "docker.io" && "${remainder}" != */* ]]; then
      printf 'docker.io/library/%s\n' "${remainder}"
    else
      printf '%s\n' "${image}"
    fi
  else
    printf 'docker.io/%s\n' "${image}"
  fi
}

declare -A allowed=()
declare -A allowed_targets=()
while IFS= read -r image; do
  [[ -n "${image}" ]] || continue
  allowed["$(normalize_image "${image}")"]=1
done < <(yq -r '.spec.images[].source' "${manifest}")
while IFS= read -r target; do
  [[ -n "${target}" ]] || continue
  allowed_targets["${target}"]=1
done < <(yq -r '.spec.images[].target' "${manifest}")

missing=0
for rendered in "$@"; do
  [[ -f "${rendered}" ]] || { printf 'Rendered manifest not found: %s\n' "${rendered}" >&2; exit 2; }
  while IFS= read -r image; do
    [[ -z "${image}" || "${image}" == "---" ]] && continue
    normalized="$(normalize_image "${image}")"
    target_path="${normalized#*/}"
    if [[ -z "${allowed[${normalized}]:-}" && -z "${allowed_targets[${target_path}]:-}" ]]; then
      printf 'MISSING\t%s\t%s\n' "${normalized}" "${rendered}"
      missing=1
    fi
  done < <(yq -r '.. | select(tag == "!!map" and has("image")) | .image | select(tag == "!!str")' "${rendered}" | sort -u)
done

if (( missing != 0 )); then
  printf 'Add every missing image at the exact rendered reference before export.\n' >&2
  exit 1
fi

printf 'Every literal rendered image is present in %s.\n' "${manifest}"
