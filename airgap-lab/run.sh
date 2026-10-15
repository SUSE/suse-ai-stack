#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inventory="${AIF_AIRGAP_INVENTORY:-${lab_dir}/generated/inventory.yml}"
vars_file="${AIF_AIRGAP_VARS:-${lab_dir}/generated/vars.yml}"
manifest="${AIF_AIRGAP_MANIFEST:-${lab_dir}/artifacts.yml}"
bundle_dir="${AIF_AIRGAP_BUNDLE:-${lab_dir}/bundles/current}"
profile="${AIF_AIRGAP_PROFILE:-suse}"
discovered_vars="${lab_dir}/generated/discovered-vars.yml"

case "${profile}" in
  core|suse|chatbot|vendor|all) ;;
  *) printf 'Unsupported AIF_AIRGAP_PROFILE: %s\n' "${profile}" >&2; exit 2 ;;
esac

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
    "  reconnect           Reopen lab egress and registry pulls for topology changes" \
    "  configure           Trust CA, configure RKE2 mirrors, and disable upstream fallback" \
    "  gpu-prepare         Check configured GPUs and inventory their runtime images" \
    "  install             Install/configure AIF (combined or separate UI mode)" \
    "  isolate             Enable reversible host and pod egress rejection" \
    "  discover-targets    Discover the downstream Rancher cluster ID" \
    "  clean-catalog       Retire legacy synthetic lab entries from the active catalog" \
    "  suse-blueprints     Publish custom Qdrant and Ollama Blueprints to private Gitea" \
    "  suse-apps           Deploy those CPU applications and test their APIs on every target" \
    "  verify              Run positive internal and negative external probes" \
    "  restore             Remove only the lab's nftables isolation table" \
    "" \
    "Profiles: AIF_AIRGAP_PROFILE=core|suse|chatbot|vendor|all (default: suse)" \
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
  local args=(-i "${inventory}" -e "@${lab_dir}/vars.example.yml" -e "@${vars_file}")
  # Discovery produces this file, so importing a previous run's copy would
  # make its output variables override the task's newly registered result.
  if [[ "${phase:-}" != discover-targets && -f "${discovered_vars}" ]]; then
    args+=( -e "@${discovered_vars}" )
  fi
  args+=( -e "airgap_profile=${profile}" )
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
  reconnect)
    require_config
    play "${lab_dir}/playbooks/00-reconnect-nodes.yml"
    ;;
  configure)
    require_config
    play "${lab_dir}/playbooks/02-configure-nodes.yml"
    ;;
  gpu-prepare)
    require_config
    play "${lab_dir}/playbooks/02-gpu-prepare.yml"
    "${lab_dir}/scripts/gpu-artifacts.sh"
    ;;
  install)
    require_config
    play "${lab_dir}/playbooks/03-install-aif.yml"
    ;;
  isolate)
    require_config
    play "${lab_dir}/playbooks/04-enable-isolation.yml"
    ;;
  discover-targets)
    require_config
    play "${lab_dir}/playbooks/05-discover-targets.yml"
    ;;
  clean-catalog)
    require_config
    play "${lab_dir}/playbooks/05-clean-catalog.yml"
    ;;
  suse-blueprints|suse-apps)
    require_config
    deploy=true
    [[ "${phase}" == suse-blueprints ]] && deploy=false
    play -e "suse_apps_deploy=${deploy}" "${lab_dir}/playbooks/05-suse-apps.yml"
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
