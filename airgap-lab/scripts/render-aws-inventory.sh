#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
project_dir="$(cd "${lab_dir}/.." && pwd)"
terraform_dir="${project_dir}/roles/vm/terraform"
metadata="${lab_dir}/generated/lab-metadata.yml"
inventory="${AIF_AIRGAP_INVENTORY:-${lab_dir}/generated/inventory.yml}"
lab_vars="${AIF_AIRGAP_VARS:-${lab_dir}/generated/vars.yml}"
stack_vars="${AIF_AIRGAP_STACK_VARS:-${lab_dir}/generated/stack-vars.yml}"

for command_name in jq tofu yq; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done
[[ -f "${metadata}" && -f "${stack_vars}" && -f "${lab_vars}" ]] || {
  printf 'Run airgap-lab/scripts/prepare-aws.sh first.\n' >&2
  exit 2
}

expected_workspace="$(yq -r '.workspace' "${metadata}")"
actual_workspace="$(tofu -chdir="${terraform_dir}" workspace show)"
[[ "${actual_workspace}" == "${expected_workspace}" ]] || {
  printf 'Refusing to read workspace %s; expected %s.\n' "${actual_workspace}" "${expected_workspace}" >&2
  exit 1
}

outputs="$(tofu -chdir="${terraform_dir}" output -json)"
output_value() {
  jq -er --arg name "$1" '.[$name].value | select(. != null and . != "")' <<<"${outputs}"
}

output_value mgmt_instance_public_ip >/dev/null
management_private_ip="$(output_value mgmt_instance_private_ip)"
output_value suse_ai_instance_public_ip >/dev/null
downstream_private_ip="$(output_value suse_ai_instance_private_ip)"
management_api_dns="$(output_value mgmt_kubeapi_fqdn)"
downstream_api_dns="$(output_value suse_ai_kubeapi_fqdn)"
output_value airgap_services_public_ip >/dev/null
services_private_ip="$(output_value airgap_services_private_ip)"
ansible_user="$(yq -r '.vm_ansible_user // .cluster.user // "ec2-user"' "${stack_vars}")"
ssh_private_key="$(yq -r '.ansible_ssh_private_key_file' "${stack_vars}")"

jq --arg user "${ansible_user}" --arg key "${ssh_private_key}" \
  -f "${script_dir}/aws-inventory.jq" <<<"${outputs}" | yq -P '.' > "${inventory}"

SERVICES_PRIVATE_IP="${services_private_ip}" \
MANAGEMENT_PRIVATE_IP="${management_private_ip}" \
DOWNSTREAM_PRIVATE_IP="${downstream_private_ip}" \
MANAGEMENT_API_DNS="${management_api_dns}" \
DOWNSTREAM_API_DNS="${downstream_api_dns}" \
yq -i '
  .airgap_services_address = strenv(SERVICES_PRIVATE_IP) |
  .airgap_host_records = [
    {"ip": strenv(SERVICES_PRIVATE_IP), "names": [.harbor_hostname, .gitea_hostname]},
    {"ip": strenv(MANAGEMENT_PRIVATE_IP), "names": ["suse-rancher.demo"]},
    {"ip": strenv(MANAGEMENT_PRIVATE_IP), "names": [strenv(MANAGEMENT_API_DNS)]},
    {"ip": strenv(DOWNSTREAM_PRIVATE_IP), "names": [strenv(DOWNSTREAM_API_DNS)]}
  ]
' "${lab_vars}"

chmod 600 "${inventory}" "${lab_vars}"
printf 'Rendered AWS control-plane/worker inventory and private host mappings.\n'
