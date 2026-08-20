#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="${project_dir}/airgap-lab"
terraform_dir="${project_dir}/roles/vm/terraform"
metadata="${lab_dir}/generated/lab-metadata.yml"

[[ -f "${metadata}" ]] || {
  printf 'No generated lab metadata found. Run setup_airgap_lab.sh --prepare-only first.\n' >&2
  exit 2
}

workspace="$(yq -r '.workspace' "${metadata}")"
stack_vars="$(yq -r '.stackVars' "${metadata}")"
[[ "${workspace}" == "${AIF_AIRGAP_TOFU_WORKSPACE:-suseai-882-airgap}" ]] || {
  printf 'Refusing to destroy unexpected workspace: %s\n' "${workspace}" >&2
  exit 1
}

tofu -chdir="${terraform_dir}" init -input=false >/dev/null
tofu -chdir="${terraform_dir}" workspace select "${workspace}" >/dev/null
[[ "$(tofu -chdir="${terraform_dir}" workspace show)" == "${workspace}" ]] || {
  printf 'Workspace guard failed; nothing was destroyed.\n' >&2
  exit 1
}

if [[ -f "${lab_dir}/generated/inventory.yml" ]]; then
  "${lab_dir}/run.sh" restore || printf 'Warning: nodes were unavailable for gate restoration; continuing with AWS destroy.\n' >&2
fi

EXTRA_VARS_FILE="${stack_vars}" "${project_dir}/destroy_private_ai_stack.sh"
find "${lab_dir}/generated/state/${workspace}" -type f -name '*.complete' -delete 2>/dev/null || true

printf 'Destroyed only the AWS resources tracked in workspace %s.\n' "${workspace}"
printf 'Bundles and evidence were retained under %s.\n' "${lab_dir}"
