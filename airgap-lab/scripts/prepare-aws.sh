#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lab_dir="$(cd "${script_dir}/.." && pwd)"
project_dir="$(cd "${lab_dir}/.." && pwd)"
base_vars="${AIF_AIRGAP_BASE_VARS:-${project_dir}/extra_vars.yml}"
generated_dir="${lab_dir}/generated"
stack_vars="${AIF_AIRGAP_STACK_VARS:-${generated_dir}/stack-vars.yml}"
lab_vars="${AIF_AIRGAP_VARS:-${generated_dir}/vars.yml}"
source_dir="${AIF_SOURCE_DIR:-$(cd "${project_dir}/.." && pwd)/aif}"
workspace="${AIF_AIRGAP_TOFU_WORKSPACE:-suseai-882-airgap}"

for command_name in curl git openssl ssh-keygen yq; do
  command -v "${command_name}" >/dev/null || {
    printf 'Required command not found: %s\n' "${command_name}" >&2
    exit 2
  }
done

[[ -f "${base_vars}" ]] || {
  printf 'AWS credential/configuration file not found: %s\n' "${base_vars}" >&2
  exit 2
}
[[ -d "${source_dir}/.git" && -f "${source_dir}/charts/aif-operator/Chart.yaml" ]] || {
  printf 'AIF source checkout not found or incomplete: %s\n' "${source_dir}" >&2
  exit 2
}

required_paths=(
  .aws_access_key
  .aws_secret_key
  .aws_region
  .aws_az1
  .aws_az2
  .aws_resource_owner
  .aws_resource_prefix
  .aws_ssh_key_name
  .aws_ssh_public_key
  .registration_email
  .sles_registration_code
)
for path in "${required_paths[@]}"; do
  if ! yq -e "${path} != null and (${path} | tostring | length) > 0 and (${path} | tostring | test(\"(?i)(<.*>|REPLACE_WITH|Your AWS)\") | not)" "${base_vars}" >/dev/null; then
    printf 'Required value %s is missing or still a placeholder in %s\n' "${path}" "${base_vars}" >&2
    exit 2
  fi
done

controller_cidr="${AIF_AIRGAP_CONTROLLER_CIDR:-}"
if [[ -z "${controller_cidr}" && -f "${stack_vars}" ]]; then
  controller_cidr="$(yq -r '.airgap_services.controller_cidr // ""' "${stack_vars}")"
fi
if [[ -z "${controller_cidr}" ]]; then
  controller_ip="$(curl --fail --silent --show-error --max-time 15 https://checkip.amazonaws.com | tr -d '[:space:]')"
  controller_cidr="${controller_ip}/32"
fi
[[ "${controller_cidr}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || {
  printf 'AIF_AIRGAP_CONTROLLER_CIDR must be an IPv4 CIDR, got: %s\n' "${controller_cidr}" >&2
  exit 2
}

configured_public_key="$(yq -r '.aws_ssh_public_key' "${base_vars}" | awk '{print $1, $2}')"
ssh_private_key="${AIF_AIRGAP_SSH_PRIVATE_KEY:-}"
if [[ -z "${ssh_private_key}" ]]; then
  for candidate in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_rsa" "${HOME}/.ssh/thb-aws.pem"; do
    [[ -f "${candidate}" ]] || continue
    derived_public_key="$(ssh-keygen -y -f "${candidate}" 2>/dev/null | awk '{print $1, $2}' || true)"
    if [[ "${configured_public_key}" == "${derived_public_key}" ]]; then
      ssh_private_key="${candidate}"
      break
    fi
  done
fi
[[ -f "${ssh_private_key}" ]] || {
  printf 'No local private key matches aws_ssh_public_key; set AIF_AIRGAP_SSH_PRIVATE_KEY.\n' >&2
  exit 2
}

mkdir -p "${generated_dir}/state"
chmod 700 "${generated_dir}" "${generated_dir}/state"

existing_value() {
  local file=$1 path=$2
  [[ -f "${file}" ]] || return 0
  yq -r "${path} // \"\"" "${file}"
}

random_hex() {
  openssl rand -hex "${1:-24}"
}

management_token="$(existing_value "${stack_vars}" '.cluster.token')"
downstream_token="$(existing_value "${stack_vars}" '.suse_ai_cluster.token')"
rancher_password="$(existing_value "${stack_vars}" '.rancher_bootstrap_password')"
services_token="$(existing_value "${lab_vars}" '.rke2.token')"
harbor_password="$(existing_value "${lab_vars}" '.harbor_admin_password')"
gitea_password="$(existing_value "${lab_vars}" '.gitea_admin_password')"
existing_services_address="$(existing_value "${lab_vars}" '.airgap_services_address')"
existing_host_records="$(if [[ -f "${lab_vars}" ]]; then yq -o=json -I=0 '.airgap_host_records // []' "${lab_vars}"; else printf '[]'; fi)"
existing_install_mode="$(existing_value "${lab_vars}" '.aif_install_mode')"
existing_gitea_tls="$(existing_value "${lab_vars}" '.gitea_tls_enabled')"
requested_install_mode="${AIF_AIRGAP_INSTALL_MODE:-${existing_install_mode:-combined}}"

[[ "${requested_install_mode}" == combined || "${requested_install_mode}" == separate ]] || {
  printf 'AIF_AIRGAP_INSTALL_MODE must be combined or separate, got: %s\n' \
    "${requested_install_mode}" >&2
  exit 2
}

[[ -n "${management_token}" ]] || management_token="$(random_hex 24)"
[[ -n "${downstream_token}" ]] || downstream_token="$(random_hex 24)"
[[ -n "${rancher_password}" ]] || rancher_password="$(random_hex 18)"
[[ -n "${services_token}" && "${services_token}" != REPLACE_WITH* ]] || services_token="$(random_hex 24)"
[[ -n "${harbor_password}" && "${harbor_password}" != REPLACE_WITH* ]] || harbor_password="$(random_hex 24)"
[[ -n "${gitea_password}" && "${gitea_password}" != REPLACE_WITH* ]] || gitea_password="$(random_hex 24)"

base_prefix="$(yq -r '.aws_resource_prefix' "${base_vars}")"
base_key_name="$(yq -r '.aws_ssh_key_name' "${base_vars}")"
lab_suffix="${AIF_AIRGAP_RESOURCE_SUFFIX:-882ag}"
resource_prefix="${base_prefix:0:10}-${lab_suffix}"
key_name="${base_key_name}-${lab_suffix}"
aif_version="$(yq -r '.version' "${source_dir}/charts/aif-operator/Chart.yaml")"
aif_commit="$(git -C "${source_dir}" rev-parse HEAD)"

cp "${base_vars}" "${stack_vars}"
MANAGEMENT_TOKEN="${management_token}" \
DOWNSTREAM_TOKEN="${downstream_token}" \
RANCHER_PASSWORD="${rancher_password}" \
CONTROLLER_CIDR="${controller_cidr}" \
RESOURCE_PREFIX="${resource_prefix}" \
KEY_NAME="${key_name}" \
SSH_PRIVATE_KEY="${ssh_private_key}" \
yq -i '
  .cloud_provider = "aws" |
  .aws_resource_prefix = strenv(RESOURCE_PREFIX) |
  .aws_ssh_key_name = strenv(KEY_NAME) |
  .ansible_ssh_private_key_file = strenv(SSH_PRIVATE_KEY) |
  .enable_external_dns = false |
  .deploy_rancher_only = true |
  .enable_gpu_operator = false |
  .enable_time_slicing = false |
  .enable_nvidia_driver_pkg_install = false |
  .use_nvidia_driver_installer = false |
  .enable_vllm_deployment = false |
  .enable_milvus = false |
  .enable_milvus_cluster_deployment = false |
  .enable_opensearch = false |
  .enable_opensearch_cluster_deployment = false |
  .enable_minio_standalone_deployment = false |
  .enable_suse_observability = false |
  .enable_longhorn = false |
  .enable_ollama = false |
  .enable_open_webui = false |
  .enable_open_webui_mcpo = false |
  .pipelines_enabled = false |
  .rancher_hostname = "suse-rancher.demo" |
  .rancher_replicas = 1 |
  .display_credentials = false |
  .rancher_bootstrap_password = strenv(RANCHER_PASSWORD) |
  .suse_ai_factory = {"enabled": false, "ai_extension": {"enabled": false}} |
  .cluster = {
    "user": "ec2-user", "user_home": "/home/ec2-user",
    "root_volume_size": 100, "image_arch": "x86_64",
    "image_distro": "sles", "image_distro_version": "15-sp7",
    "instance_type_cp": "m6i.2xlarge", "instance_type_gpu": "m6i.xlarge",
    "instance_type_nongpu": "m6i.xlarge", "num_cp_nodes": 1,
    "num_worker_nodes_gpu": 0, "num_worker_nodes_nongpu": 0,
    "token": strenv(MANAGEMENT_TOKEN), "version": "v1.34.4+rke2r1"
  } |
  .suse_ai_cluster = {
    "user": "ec2-user", "user_home": "/home/ec2-user",
    "root_volume_size": 80, "image_arch": "x86_64",
    "image_distro": "sles", "image_distro_version": "15-sp7",
    "instance_type_cp": "m6i.xlarge", "instance_type_gpu": "m6i.xlarge",
    "instance_type_nongpu": "m6i.xlarge", "num_cp_nodes": 1,
    "num_worker_nodes_gpu": 0, "num_worker_nodes_nongpu": 0,
    "token": strenv(DOWNSTREAM_TOKEN), "version": "v1.34.4+rke2r1"
  } |
  .airgap_services = {
    "enabled": true, "instance_type": "m6i.xlarge",
    "root_volume_size": 120, "controller_cidr": strenv(CONTROLLER_CIDR)
  }
' "${stack_vars}"

cp "${lab_dir}/vars.example.yml" "${lab_vars}"
SERVICES_TOKEN="${services_token}" \
HARBOR_PASSWORD="${harbor_password}" \
GITEA_PASSWORD="${gitea_password}" \
AIF_VERSION="${aif_version}" \
REGISTRATION_EMAIL="$(yq -r '.registration_email // ""' "${base_vars}")" \
SLES_CODE="$(yq -r '.sles_registration_code // ""' "${base_vars}")" \
SLE_MICRO_CODE="$(yq -r '.sle_micro_registration_code // ""' "${base_vars}")" \
yq -i '
  .harbor_admin_password = strenv(HARBOR_PASSWORD) |
  .harbor_registry_password = strenv(HARBOR_PASSWORD) |
  .gitea_admin_password = strenv(GITEA_PASSWORD) |
  .rke2.token = strenv(SERVICES_TOKEN) |
  .rke2.version = "v1.34.4+rke2r1" |
  .scc_registration.email = strenv(REGISTRATION_EMAIL) |
  .scc_registration.sles_code = strenv(SLES_CODE) |
  .scc_registration.sle_micro_code = strenv(SLE_MICRO_CODE) |
  .suse_packages = ["curl", "git", "gzip", "jq", "pciutils", "rsync", "skopeo", "tar"] |
  .aif_version = strenv(AIF_VERSION) |
  .aif_registry_ca_mode = "settings" |
  .aif_install_mode = "combined" |
  .harbor_registry_storage_size = "40Gi" |
  .airgap_remote_bundle_root = "/var/lib/aif-airgap-lab/bundles" |
  .controller_yq_path = "/usr/bin/yq"
' "${lab_vars}"

if [[ -n "${existing_services_address}" ]]; then
  EXISTING_SERVICES_ADDRESS="${existing_services_address}" \
    yq -i '.airgap_services_address = strenv(EXISTING_SERVICES_ADDRESS)' "${lab_vars}"
fi
if [[ "${existing_host_records}" != "[]" ]]; then
  EXISTING_HOST_RECORDS="${existing_host_records}" \
    yq -i '.airgap_host_records = (strenv(EXISTING_HOST_RECORDS) | from_json)' "${lab_vars}"
fi
REQUESTED_INSTALL_MODE="${requested_install_mode}" \
  yq -i '.aif_install_mode = strenv(REQUESTED_INSTALL_MODE)' "${lab_vars}"
if [[ "${existing_gitea_tls}" == true || "${existing_gitea_tls}" == false ]]; then
  EXISTING_GITEA_TLS="${existing_gitea_tls}" \
    yq -i '.gitea_tls_enabled = (strenv(EXISTING_GITEA_TLS) == "true")' "${lab_vars}"
fi

chmod 600 "${stack_vars}" "${lab_vars}"

LAB_WORKSPACE="${workspace}" \
LAB_STACK_VARS="${stack_vars}" \
LAB_VARS="${lab_vars}" \
LAB_SOURCE_DIR="${source_dir}" \
LAB_SOURCE_COMMIT="${aif_commit}" \
LAB_AIF_VERSION="${aif_version}" \
yq -n '
  {
    "workspace": strenv(LAB_WORKSPACE),
    "stackVars": strenv(LAB_STACK_VARS),
    "labVars": strenv(LAB_VARS),
    "sourceDir": strenv(LAB_SOURCE_DIR),
    "sourceCommit": strenv(LAB_SOURCE_COMMIT),
    "aifVersion": strenv(LAB_AIF_VERSION)
  }
' > "${generated_dir}/lab-metadata.yml"
chmod 600 "${generated_dir}/lab-metadata.yml"

printf 'Prepared CPU-only AWS lab configuration.\n'
printf '  Workspace: %s\n' "${workspace}"
printf '  Region: %s\n' "$(yq -r '.aws_region' "${stack_vars}")"
printf '  Resource prefix: %s\n' "${resource_prefix}"
printf '  Nodes: management=m6i.2xlarge, downstream=m6i.xlarge, services=m6i.xlarge\n'
printf '  AIF source: %s (%s)\n' "${aif_commit:0:12}" "${aif_version}"
printf '  AIF install mode: %s\n' "${requested_install_mode}"
printf 'Generated credentials remain in ignored mode-0600 files under %s.\n' "${generated_dir}"
