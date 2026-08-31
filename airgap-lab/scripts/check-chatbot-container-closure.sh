#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
manifest="${lab_dir}/artifacts.yml"
source_dir="${AIF_SOURCE_DIR:-$(cd "${lab_dir}/../.." && pwd)/aif}"

usage() {
  printf '%s\n' \
    "Usage: $0 [--manifest FILE] [--source-dir AIF-DIR]" \
    "Renders the pinned Simple Chatbot with RAG values and verifies that the" \
    "chatbot profile contains every chart and literal container image."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest=$2; shift 2 ;;
    --source-dir) source_dir=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for command_name in helm yq; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done
[[ -f "${manifest}" ]] || { printf 'Manifest not found: %s\n' "${manifest}" >&2; exit 2; }
[[ -d "${source_dir}" ]] || { printf 'AIF source directory not found: %s\n' "${source_dir}" >&2; exit 2; }

blueprint_name="$(yq -r '.metadata.annotations."airgap.ai-factory.suse.com/chatbot-blueprint-name"' "${manifest}")"
blueprint_version="$(yq -r '.metadata.annotations."airgap.ai-factory.suse.com/chatbot-blueprint-version"' "${manifest}")"
if [[ -z "${blueprint_name}" || "${blueprint_name}" == "null" || \
      -z "${blueprint_version}" || "${blueprint_version}" == "null" ]]; then
  printf 'Manifest must pin the chatbot Blueprint name and version annotations.\n' >&2
  exit 1
fi
blueprint="${source_dir}/charts/aif-operator/files/blueprints/${blueprint_name}-${blueprint_version}.yaml"
[[ -f "${blueprint}" ]] || { printf 'Pinned Blueprint not found: %s\n' "${blueprint}" >&2; exit 1; }

actual_family="$(yq -r '.metadata.labels."ai-factory.suse.com/blueprint-name"' "${blueprint}")"
actual_version="$(yq -r '.spec.version' "${blueprint}")"
if [[ "${actual_family}" != "${blueprint_name}" || "${actual_version}" != "${blueprint_version}" ]]; then
  printf 'Blueprint identity mismatch: family=%s version=%s\n' "${actual_family}" "${actual_version}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
cleanup() { rm -rf -- "${work_dir}"; }
trap cleanup EXIT
export HELM_REGISTRY_CONFIG="${work_dir}/registry.json"
export HELM_REPOSITORY_CONFIG="${work_dir}/repositories.yaml"
export HELM_REPOSITORY_CACHE="${work_dir}/repository-cache"
if [[ -n "${APPCO_USERNAME:-}" || -n "${APPCO_PASSWORD:-}" ]]; then
  : "${APPCO_USERNAME:?Set APPCO_USERNAME together with APPCO_PASSWORD}"
  : "${APPCO_PASSWORD:?Set APPCO_PASSWORD together with APPCO_USERNAME}"
  printf '%s' "${APPCO_PASSWORD}" | helm registry login dp.apps.rancher.io \
    --username "${APPCO_USERNAME}" --password-stdin >/dev/null
fi

declare -a rendered_manifests=()
component_count="$(yq -r '.spec.components | length' "${blueprint}")"
for ((component_index=0; component_index<component_count; component_index++)); do
  chart_name="$(yq -r ".spec.components[${component_index}].chartName" "${blueprint}")"
  chart_repo="$(yq -r ".spec.components[${component_index}].chartRepo" "${blueprint}")"
  chart_version="$(yq -r ".spec.components[${component_index}].chartVersion" "${blueprint}")"
  chart_id="appco-${chart_name}"

  [[ "${chart_repo}" == "application-collection" ]] || {
    printf 'Unexpected chart repository for %s: %s\n' "${chart_name}" "${chart_repo}" >&2
    exit 1
  }
  manifest_version="$(yq -r ".spec.charts[] | select(.id == \"${chart_id}\") | .version" "${manifest}")"
  manifest_source="$(yq -r ".spec.charts[] | select(.id == \"${chart_id}\") | .source" "${manifest}")"
  manifest_profiles="$(yq -r ".spec.charts[] | select(.id == \"${chart_id}\") | .profiles | join(\",\")" "${manifest}")"
  expected_source="oci://dp.apps.rancher.io/charts/${chart_name}"
  if [[ "${manifest_version}" != "${chart_version}" || \
        "${manifest_source}" != "${expected_source}" || \
        ",${manifest_profiles}," != *",chatbot,"* ]]; then
    printf 'Chatbot profile does not contain %s %s.\n' "${chart_name}" "${chart_version}" >&2
    exit 1
  fi

  archive="${work_dir}/${chart_name}-${chart_version}.tgz"
  helm pull "oci://dp.apps.rancher.io/charts/${chart_name}" \
    --version "${chart_version}" --destination "${work_dir}" >/dev/null
  rendered="${work_dir}/${chart_name}.yaml"
  yq -r ".spec.components[${component_index}].values" "${blueprint}" \
    | helm template "${chart_name}" "${archive}" \
        --namespace simple-chatbot-with-rag-system -f - > "${rendered}"
  rendered_manifests+=("${rendered}")
done

"${script_dir}/check-rendered-images.sh" \
  --manifest "${manifest}" --profile chatbot "${rendered_manifests[@]}"
printf 'Chatbot chart/container closure matches %s %s.\n' "${blueprint_name}" "${blueprint_version}"
