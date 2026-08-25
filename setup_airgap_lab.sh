#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="${project_dir}/airgap-lab"
terraform_dir="${project_dir}/roles/vm/terraform"
base_vars="${AIF_AIRGAP_BASE_VARS:-${project_dir}/extra_vars.yml}"
workspace="${AIF_AIRGAP_TOFU_WORKSPACE:-suseai-882-airgap}"
source_dir="${AIF_SOURCE_DIR:-$(cd "${project_dir}/.." && pwd)/aif}"
profile="${AIF_AIRGAP_PROFILE:-core}"

usage() {
  printf '%s\n' \
    "Usage: $0 [--status|--prepare-only|--reset-progress]" \
    "" \
    "With no arguments, provisions and qualifies the complete CPU-only AWS lab." \
    "A failed run is resumable by running the same command again." \
    "" \
    "  --status          Show completed phase markers and current AWS workspace" \
    "  --prepare-only    Generate ignored configuration without creating AWS resources" \
    "  --reset-progress  Forget phase markers; resources are retained and reconciled"
}

mode=run
case "${1:-}" in
  "") ;;
  --status) mode=status ;;
  --prepare-only) mode=prepare ;;
  --reset-progress) mode=reset ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

for command_name in ansible-galaxy ansible-playbook docker git helm jq skopeo tofu yq; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done

"${lab_dir}/scripts/check-shell-safety.sh"
AIF_AIRGAP_BASE_VARS="${base_vars}" "${lab_dir}/scripts/prepare-aws.sh"
metadata="${lab_dir}/generated/lab-metadata.yml"
stack_vars="$(yq -r '.stackVars' "${metadata}")"
lab_vars="$(yq -r '.labVars' "${metadata}")"
aif_commit="$(yq -r '.sourceCommit' "${metadata}")"
short_commit="${aif_commit:0:12}"
install_mode="$(yq -r '.aif_install_mode' "${lab_vars}")"
ca_mode="$(yq -r '.aif_registry_ca_mode' "${lab_vars}")"
gitea_tls_enabled="$(yq -r '.gitea_tls_enabled' "${lab_vars}")"
if [[ "${gitea_tls_enabled}" == true ]]; then
  git_transport=https
else
  git_transport=http
fi
manifest="${lab_dir}/generated/artifacts-aif-source.yml"
bundle="${AIF_AIRGAP_BUNDLE:-${lab_dir}/bundles/aif-${short_commit}-${profile}}"
bundle_local_sources_match() {
  local candidate=$1 index count source expected actual
  count="$(yq -r '.spec.images | length' "${manifest}")"
  for ((index=0; index<count; index++)); do
    [[ "$(yq -r ".spec.images[${index}].sourceTransport // \"docker\"" "${manifest}")" == docker-daemon ]] || continue
    source="$(yq -r ".spec.images[${index}].source" "${manifest}")"
    expected="$(awk -F '\t' -v source="${source}" '$1 == "image" && $2 == source {print $3}' "${candidate}/SOURCE-DIGESTS.txt")"
    actual="$(skopeo inspect --format '{{.Digest}}' "docker-daemon:${source}" 2>/dev/null || true)"
    [[ -n "${expected}" && "${expected}" == "${actual}" ]] || return 1
  done
}
if [[ -z "${AIF_AIRGAP_BUNDLE:-}" && ! -d "${bundle}" ]]; then
  shopt -s nullglob
  for candidate in "${lab_dir}/bundles/aif-${short_commit}"*; do
    [[ -f "${candidate}/METADATA" && -f "${candidate}/ARTIFACTS.yaml" ]] || continue
    candidate_profile="$(awk -F= '$1 == "profile" {print $2}' "${candidate}/METADATA")"
    candidate_commit="$(yq -r '.metadata.annotations."airgap.ai-factory.suse.com/source-commit" // ""' "${candidate}/ARTIFACTS.yaml")"
    candidate_manifest_digest="$(awk -F= '$1 == "manifest_sha256" {print $2}' "${candidate}/METADATA")"
    current_manifest_digest="$(sha256sum "${manifest}" 2>/dev/null | awk '{print $1}')"
    if [[ "${candidate_profile}" == "${profile}" \
       && "${candidate_commit}" == "${aif_commit}" \
       && -n "${current_manifest_digest}" \
       && "${candidate_manifest_digest}" == "${current_manifest_digest}" ]] \
       && bundle_local_sources_match "${candidate}"; then
      bundle="${candidate}"
      break
    fi
  done
  shopt -u nullglob
fi
state_root="${lab_dir}/generated/state/${workspace}"
run_state="${state_root}/runs/${short_commit}-${profile}"
qualification_key="${install_mode}-${ca_mode}-git-${git_transport}"
qualification_state="${run_state}/qualifications/${qualification_key}"
active_qualification_file="${run_state}/active-qualification"
services_git_transport_file="${state_root}/services-git-transport"
mkdir -p "${state_root}" "${run_state}" "${qualification_state}"
chmod 700 "${state_root}" "${state_root}/runs" "${run_state}" \
  "${run_state}/qualifications" "${qualification_state}"

select_workspace() {
  tofu -chdir="${terraform_dir}" init -input=false >/dev/null
  if tofu -chdir="${terraform_dir}" workspace list \
      | sed -E 's/^[* ]+//' | grep -Fxq "${workspace}"; then
    tofu -chdir="${terraform_dir}" workspace select "${workspace}" >/dev/null
  else
    tofu -chdir="${terraform_dir}" workspace new "${workspace}" >/dev/null
  fi
  actual_workspace="$(tofu -chdir="${terraform_dir}" workspace show)"
  [[ "${actual_workspace}" == "${workspace}" ]] || {
    printf 'Workspace guard failed: expected %s, selected %s.\n' "${workspace}" "${actual_workspace}" >&2
    exit 1
  }
}

select_workspace

if [[ "${mode}" == status ]]; then
  printf 'OpenTofu workspace: %s\n' "${workspace}"
  printf 'Source commit: %s\n' "${short_commit}"
  printf 'Requested AIF install mode: %s\n' "${install_mode}"
  printf 'Requested registry CA mode: %s\n' "${ca_mode}"
  printf 'Requested Git transport: %s\n' "${git_transport}"
  if [[ -f "${active_qualification_file}" ]]; then
    printf 'Active qualified AIF profile: %s\n' "$(<"${active_qualification_file}")"
  else
    printf 'Active qualified AIF profile: not recorded\n'
  fi
  printf 'Bundle: %s\n' "${bundle}"
  if find "${state_root}" -type f -name '*.complete' -print -quit | grep -q .; then
    find "${state_root}" -type f -name '*.complete' -printf '  complete: %P\n' | sort
  else
    printf '  No completed phases recorded.\n'
  fi
  exit 0
fi

if [[ "${mode}" == prepare ]]; then
  printf 'Preparation complete; no AWS resources were changed.\n'
  exit 0
fi

if [[ "${mode}" == reset ]]; then
  find "${state_root}" -type f -name '*.complete' -delete
  printf 'Progress markers reset. AWS resources and generated credentials were retained.\n'
  exit 0
fi

active_qualification=""
if [[ -f "${active_qualification_file}" ]]; then
  active_qualification="$(<"${active_qualification_file}")"
fi
if [[ "${active_qualification}" != "${qualification_key}" ]]; then
  find "${qualification_state}" -type f -name '*.complete' -delete
  if [[ -n "${active_qualification}" ]]; then
    printf '[mode] Requalifying transition from %s to %s.\n' \
      "${active_qualification}" "${qualification_key}"
  else
    printf '[mode] No active qualification checkpoint; qualifying %s.\n' \
      "${qualification_key}"
  fi
fi

run_step() {
  local marker=$1 description=$2
  shift 2
  if [[ -f "${marker}" ]]; then
    printf '[skip] %s\n' "${description}"
    return 0
  fi
  printf '[run ] %s\n' "${description}"
  "$@"
  date -u +%Y-%m-%dT%H:%M:%SZ > "${marker}"
  chmod 600 "${marker}"
}

stack_state_present() {
  local resources
  resources="$(tofu -chdir="${terraform_dir}" state list 2>/dev/null || true)"
  grep -Fxq 'aws_instance.cp_master' <<<"${resources}" \
    && grep -Fxq 'aws_instance.suse_ai_cp_master[0]' <<<"${resources}" \
    && grep -Fxq 'aws_instance.airgap_services[0]' <<<"${resources}"
}

if [[ -f "${state_root}/stack.complete" ]] && ! stack_state_present; then
  printf 'AWS state no longer contains the complete topology; clearing stale progress markers.\n'
  find "${state_root}" -type f -name '*.complete' -delete
fi

# A reset removes the stack marker but deliberately retains the nodes. Those
# nodes may still carry the previous qualification's fail-closed nftables
# table, which would make the connected bootstrap wait forever for SUSE cloud
# registration. Remove only the lab-owned isolation rules before reconciling
# the connected stage; the isolate phase installs them again before AIF is
# qualified.
if stack_state_present \
   && [[ ! -f "${state_root}/stack.complete" ]] \
   && [[ -f "${lab_dir}/generated/inventory.yml" ]]; then
  printf '[mode] Reopening egress for connected stack reconciliation.\n'
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" restore
fi

run_step "${run_state}/collections.complete" "Install Ansible collections" \
  ansible-galaxy collection install -r "${lab_dir}/requirements.yml"

run_step "${run_state}/source-build.complete" "Build exact AIF source artifacts" \
  env AIF_SOURCE_DIR="${source_dir}" AIF_SOURCE_MANIFEST="${manifest}" \
    "${lab_dir}/run.sh" build-aif-source

run_step "${run_state}/bundle-export.complete" "Export the checksummed core media bundle" \
  env AIF_AIRGAP_MANIFEST="${manifest}" AIF_AIRGAP_BUNDLE="${bundle}" \
    AIF_AIRGAP_PROFILE="${profile}" "${lab_dir}/run.sh" mirror-export

run_step "${state_root}/stack.complete" "Provision management, downstream and services nodes; install RKE2/Rancher" \
  env EXTRA_VARS_FILE="${stack_vars}" AIF_AIRGAP_OVERLAY=true \
    "${project_dir}/setup_private_ai_stack.sh"

run_step "${state_root}/inventory.complete" "Render the AWS inventory from private/public outputs" \
  "${lab_dir}/scripts/render-aws-inventory.sh"

run_step "${state_root}/services-bootstrap.complete" "Bootstrap the connected CPU-only services cluster" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" bootstrap-services

if [[ -f "${state_root}/services.complete" ]] \
   && [[ ! -f "${services_git_transport_file}" \
      || "$(<"${services_git_transport_file}")" != "${git_transport}" ]]; then
  printf '[mode] Gitea transport changed; reconciling the services phase.\n'
  rm -f "${state_root}/services.complete"
fi
run_step "${state_root}/services.complete" "Install private-CA Harbor and authenticated Gitea" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" services
printf '%s\n' "${git_transport}" > "${services_git_transport_file}.tmp"
chmod 600 "${services_git_transport_file}.tmp"
mv "${services_git_transport_file}.tmp" "${services_git_transport_file}"

run_step "${run_state}/bundle-import.complete" "Transfer and import the media bundle inside the gated VPC" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" transfer-import

run_step "${state_root}/configure.complete" "Configure private trust and fail-closed RKE2 mirrors" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" configure

run_step "${state_root}/isolate.complete" "Close public host and pod egress on AIF nodes" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" isolate

run_step "${qualification_state}/install.complete" "Install PR-source AIF from Harbor (${qualification_key})" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" install

printf '%s\n' "${qualification_key}" > "${active_qualification_file}.tmp"
chmod 600 "${active_qualification_file}.tmp"
mv "${active_qualification_file}.tmp" "${active_qualification_file}"

run_step "${run_state}/targets.complete" "Discover local and downstream Rancher targets" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" discover-targets

run_step "${qualification_state}/matrix.complete" "Run FleetBundle and GitOps in single- and multi-cluster modes (${qualification_key})" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" matrix

run_step "${qualification_state}/verify.complete" "Collect positive private-path and negative public-egress evidence (${qualification_key})" \
  env AIF_AIRGAP_BUNDLE="${bundle}" AIF_AIRGAP_PROFILE="${profile}" \
    "${lab_dir}/run.sh" verify

printf '\nAir-gap qualification completed successfully.\n'
printf 'Evidence: %s\n' "${lab_dir}/generated/evidence"
printf 'Status: %s --status\n' "$0"
printf 'Destroy: %s/destroy_airgap_lab.sh\n' "${project_dir}"
