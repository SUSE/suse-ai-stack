#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
inventory="${AIF_AIRGAP_INVENTORY:-${lab_dir}/generated/inventory.yml}"
vars_file="${AIF_AIRGAP_VARS:-${lab_dir}/generated/vars.yml}"
manifest="${AIF_AIRGAP_MANIFEST:-${lab_dir}/artifacts.yml}"
bundle_dir="${AIF_AIRGAP_BUNDLE:-${lab_dir}/bundles/current}"
profile="${AIF_AIRGAP_PROFILE:-core}"

export ANSIBLE_CONFIG="${lab_dir}/ansible.cfg"

usage() {
  printf '%s\n' \
    "Usage: $0 <phase>" \
    "" \
    "Phases:" \
    "  bootstrap-services  Install CPU-only RKE2 on the services node (connected stage)" \
    "  services            Install TLS Harbor and authenticated Gitea" \
    "  mirror-export       Download selected artifacts into a checksummed transfer bundle" \
    "  mirror-import       Verify and upload a transfer bundle into Harbor" \
    "  mirror              Export and import while seed and Harbor are both reachable" \
    "  configure           Trust CA, configure RKE2 mirrors, and disable upstream fallback" \
    "  install             Install/configure AIF (combined or separate UI mode)" \
    "  isolate             Enable reversible host and pod egress rejection" \
    "  smoke               Create the no-GPU Blueprint workload fixture" \
    "  verify              Run positive internal and negative external probes" \
    "  restore             Remove only the lab's nftables isolation table" \
    "  all                 services, mirror, configure, isolate, install, smoke, verify"
}

require_config() {
  if [[ ! -f "${inventory}" || ! -f "${vars_file}" ]]; then
    printf 'Missing %s or %s. Copy the examples under generated/ first.\n' "${inventory}" "${vars_file}" >&2
    exit 2
  fi
}

play() {
  ansible-playbook -i "${inventory}" -e "@${vars_file}" "$@"
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
  services)
    require_config
    play "${lab_dir}/playbooks/01-services.yml"
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
  verify)
    require_config
    play "${lab_dir}/playbooks/06-verify.yml"
    ;;
  restore)
    require_config
    play "${lab_dir}/playbooks/99-disable-isolation.yml"
    ;;
  all)
    require_config
    play "${lab_dir}/playbooks/01-services.yml"
    mirror mirror
    play "${lab_dir}/playbooks/02-configure-nodes.yml"
    play "${lab_dir}/playbooks/04-enable-isolation.yml"
    play "${lab_dir}/playbooks/03-install-aif.yml"
    play "${lab_dir}/playbooks/05-smoke.yml"
    play "${lab_dir}/playbooks/06-verify.yml"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
