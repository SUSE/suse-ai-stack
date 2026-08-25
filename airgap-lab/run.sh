#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inventory="${AIF_AIRGAP_INVENTORY:-${lab_dir}/generated/inventory.yml}"
vars_file="${AIF_AIRGAP_VARS:-${lab_dir}/generated/vars.yml}"
manifest="${AIF_AIRGAP_MANIFEST:-${lab_dir}/artifacts.yml}"
bundle_dir="${AIF_AIRGAP_BUNDLE:-${lab_dir}/bundles/current}"
profile="${AIF_AIRGAP_PROFILE:-core}"
discovered_vars="${lab_dir}/generated/discovered-vars.yml"

export ANSIBLE_CONFIG="${lab_dir}/ansible.cfg"
"${lab_dir}/scripts/check-shell-safety.sh"

usage() {
  printf '%s\n' \
    "Usage: $0 <phase>" \
    "" \
    "Phases:" \
    "  bootstrap-services  Install CPU-only RKE2 on the services node (connected stage)" \
    "  build-aif-source    Build exact operator/UI images and charts from AIF_SOURCE_DIR" \
    "  services            Install TLS Harbor and authenticated Gitea" \
    "  transfer-import     Copy the media bundle to services and import from inside the VPC" \
    "  mirror-export       Download selected artifacts into a checksummed transfer bundle" \
    "  mirror-import       Verify and upload a transfer bundle into Harbor" \
    "  mirror              Export and import while seed and Harbor are both reachable" \
    "  configure           Trust CA, configure RKE2 mirrors, and disable upstream fallback" \
    "  install             Install/configure AIF (combined or separate UI mode)" \
    "  isolate             Enable reversible host and pod egress rejection" \
    "  smoke               Create the no-GPU Blueprint workload fixture" \
    "  discover-targets    Discover the downstream Rancher cluster ID" \
    "  matrix              Run FleetBundle/GitOps in single- and multi-cluster modes" \
    "  verify              Run positive internal and negative external probes" \
    "  restore             Remove only the lab's nftables isolation table" \
    "" \
    "Use ./setup_airgap_lab.sh for the complete ordered and resumable workflow."
}

require_config() {
  if [[ ! -f "${inventory}" || ! -f "${vars_file}" ]]; then
    printf 'Missing %s or %s. Copy the examples under generated/ first.\n' "${inventory}" "${vars_file}" >&2
    exit 2
  fi
}

play() {
  local args=(-i "${inventory}" -e "@${vars_file}")
  # Discovery produces this file, so importing a previous run's copy would
  # make its output variables override the task's newly registered result.
  if [[ "${phase:-}" != discover-targets && -f "${discovered_vars}" ]]; then
    args+=( -e "@${discovered_vars}" )
  fi
  ansible-playbook "${args[@]}" "$@"
}

mirror() {
  local operation=$1
  "${lab_dir}/scripts/artifacts.sh" "${operation}" \
    --manifest "${manifest}" \
    --bundle "${bundle_dir}" \
    --profile "${profile}"
}

phase="${1:-}"
case "${phase}" in
  bootstrap-services)
    require_config
    play "${lab_dir}/playbooks/00-bootstrap-services.yml"
    ;;
  build-aif-source)
    "${lab_dir}/scripts/build-aif-source.sh"
    ;;
  services)
    require_config
    play "${lab_dir}/playbooks/01-services.yml"
    ;;
  transfer-import)
    require_config
    play -e "airgap_bundle_dir=${bundle_dir}" -e "airgap_profile=${profile}" \
      "${lab_dir}/playbooks/01-import-bundle.yml"
    ;;
  mirror-export)
    mirror export
    ;;
  mirror-import)
    mirror import
    ;;
  mirror)
    mirror mirror
    ;;
  configure)
    require_config
    play "${lab_dir}/playbooks/02-configure-nodes.yml"
    ;;
  install)
    require_config
    play "${lab_dir}/playbooks/03-install-aif.yml"
    ;;
  isolate)
    require_config
    play "${lab_dir}/playbooks/04-enable-isolation.yml"
    ;;
  smoke)
    require_config
    play "${lab_dir}/playbooks/05-smoke.yml"
    ;;
  discover-targets)
    require_config
    play "${lab_dir}/playbooks/05-discover-targets.yml"
    ;;
  matrix)
    require_config
    [[ -f "${discovered_vars}" ]] || {
      printf 'Run the discover-targets phase before the multi-cluster matrix.\n' >&2
      exit 2
    }
    play -e smoke_strategy=FleetBundle -e smoke_workload_name=airgap-smoke-single \
      -e '{"smoke_target_clusters":["local"]}' "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=GitOps -e smoke_workload_name=airgap-smoke-single \
      -e '{"smoke_target_clusters":["local"]}' "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=FleetBundle -e smoke_workload_name=airgap-smoke-multi \
      "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=GitOps -e smoke_workload_name=airgap-smoke-multi \
      "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=FleetBundle -e smoke_application_mode=logical \
      -e smoke_workload_name=airgap-logical-single \
      -e '{"smoke_target_clusters":["local"]}' "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=GitOps -e smoke_application_mode=logical \
      -e smoke_git_auth_type=basic \
      -e smoke_workload_name=airgap-logical-single \
      -e '{"smoke_target_clusters":["local"]}' "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=FleetBundle -e smoke_application_mode=logical \
      -e smoke_workload_name=airgap-logical-multi \
      "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=FleetBundle -e smoke_application_mode=logical \
      -e smoke_blueprint_mode=preprovisioned \
      -e smoke_workload_name=airgap-blueprint-source \
      -e '{"smoke_target_clusters":["local"]}' "${lab_dir}/playbooks/05-smoke.yml"
    play -e smoke_strategy=GitOps -e smoke_application_mode=logical \
      -e smoke_git_auth_type=token \
      -e smoke_workload_name=airgap-logical-multi \
      -e smoke_verify_source_switch=true \
      "${lab_dir}/playbooks/05-smoke.yml"
    ;;
  verify)
    require_config
    play "${lab_dir}/playbooks/06-verify.yml"
    ;;
  restore)
    require_config
    play "${lab_dir}/playbooks/99-disable-isolation.yml"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
