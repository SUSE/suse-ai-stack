#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
manifest="${lab_dir}/artifacts.yml"
profile=suse
charts_dir=""
usage() {
  printf '%s\n' \
    "Usage: $0 [--manifest FILE] [--profile suse|chatbot|vendor|all] [--charts-dir DIR]" \
    "Lint and render the custom SUSE Blueprints, including hooks and init containers." \
    "Use --charts-dir with an exported bundle's charts directory for an offline check."
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest=$2; shift 2 ;;
    --profile) profile=$2; shift 2 ;;
    --charts-dir) charts_dir=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
case "${profile}" in suse|chatbot|vendor|all) ;; *) usage >&2; exit 2 ;; esac
for command_name in helm yq; do
  command -v "${command_name}" >/dev/null || { printf 'Required command not found: %s\n' "${command_name}" >&2; exit 2; }
done
[[ -f "${manifest}" ]] || { printf 'Manifest not found: %s\n' "${manifest}" >&2; exit 2; }
work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
export HELM_REGISTRY_CONFIG="${work_dir}/registry.json"
export HELM_REPOSITORY_CONFIG="${work_dir}/repositories.yaml"
export HELM_REPOSITORY_CACHE="${work_dir}/repository-cache"
if [[ -z "${charts_dir}" ]]; then
  charts_dir="${work_dir}"
  download=true
  for registry in dp.apps.rancher.io registry.suse.com; do
    if [[ "${registry}" == dp.apps.rancher.io ]]; then
      username="${APPCO_USERNAME:-}"; password="${APPCO_PASSWORD:-}"
    else
      username="${SUSE_REGISTRY_USERNAME:-}"; password="${SUSE_REGISTRY_PASSWORD:-}"
    fi
    if [[ -n "${username}" || -n "${password}" ]]; then
      [[ -n "${username}" && -n "${password}" ]] || { printf 'Both credentials are required for %s.\n' "${registry}" >&2; exit 2; }
      printf '%s' "${password}" | helm registry login "${registry}" --username "${username}" --password-stdin >/dev/null
    fi
  done
else
  download=false
fi

rendered_manifests=()
for name in suse-qdrant-airgap appco-ollama-airgap; do
  blueprint="${lab_dir}/fixtures/blueprints/${name}.yaml"
  count="$(yq -r '.spec.components | length' "${blueprint}")"
  for ((index=0; index<count; index++)); do
    chart="$(yq -r ".spec.components[${index}].chartName" "${blueprint}")"
    repo="$(yq -r ".spec.components[${index}].chartRepo" "${blueprint}")"
    version="$(yq -r ".spec.components[${index}].chartVersion" "${blueprint}")"
    release="$(yq -r ".spec.components[${index}].releaseName" "${blueprint}")"
    case "${repo}" in
      suse-ai-registry) id="suse-${chart}"; source="oci://registry.suse.com/ai/charts/${chart}"; target=aif-suse ;;
      application-collection) id="appco-${chart}"; source="oci://dp.apps.rancher.io/charts/${chart}"; target=aif-appco ;;
      *) printf 'Unexpected chart repository: %s\n' "${repo}" >&2; exit 1 ;;
    esac
    CHART_ID="${id}" CHART_VERSION="${version}" CHART_SOURCE="${source}" CHART_TARGET="${target}" PROFILE="${profile}" \
      yq -e '[.spec.charts[] | select(.id == strenv(CHART_ID) and .version == strenv(CHART_VERSION)
        and .source == strenv(CHART_SOURCE) and (.targets | contains([strenv(CHART_TARGET)]))
        and (strenv(PROFILE) == "all" or (.profiles | contains([strenv(PROFILE)])) or (.profiles | contains(["core"]))))] | length == 1' \
        "${manifest}" >/dev/null || { printf 'Missing or mismatched chart in %s profile: %s\n' "${profile}" "${id}" >&2; exit 1; }
    archive="${charts_dir}/$(CHART_ID="${id}" yq -r '.spec.charts[] | select(.id == strenv(CHART_ID)) | .archive' "${manifest}")"
    if [[ "${download}" == true ]]; then
      helm pull "${source}" --version "${version}" --destination "${charts_dir}" >/dev/null
    fi
    [[ -f "${archive}" ]] || { printf 'Chart archive not found: %s\n' "${archive}" >&2; exit 1; }
    [[ "$(helm show chart "${archive}" | yq -r '.name + ":" + .version')" == "${chart}:${version}" ]] || {
      printf 'Chart archive identity mismatch: %s\n' "${archive}" >&2; exit 1;
    }
    values="${work_dir}/${name}-${index}-values.yaml"
    rendered="${work_dir}/${name}-${index}.yaml"
    yq ".spec.components[${index}].values" "${blueprint}" > "${values}"
    helm lint "${archive}" --values "${values}"
    helm template "${release}" "${archive}" --namespace aif-suse-apps --values "${values}" > "${rendered}"
    rendered_manifests+=("${rendered}")
  done
done
"${script_dir}/check-rendered-images.sh" --manifest "${manifest}" --profile "${profile}" "${rendered_manifests[@]}"
printf 'Custom SUSE Blueprint chart/container closure passed.\n'
