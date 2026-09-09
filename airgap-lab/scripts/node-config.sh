#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${AIF_AIRGAP_NODE_CONFIG:-${lab_dir}/nodes.yml}"
if [[ ! -f "${config}" ]]; then
  if [[ -n "${AIF_AIRGAP_NODE_CONFIG:-}" ]]; then
    printf 'Node configuration not found: %s\n' "${config}" >&2
    exit 2
  fi
  config="${lab_dir}/nodes.example.yml"
fi

# Reject misspelled and unsupported options before any cloud operations. The
# lab keeps one control plane per cluster; all worker types share its OS/disk.
yq -o=json '.' "${config}" | jq -e '
  type == "object" and
  (keys - ["cluster", "suse_ai_cluster", "gpu_operator_chart_version",
           "enable_time_slicing", "time_slicing_replicas"] | length == 0) and
  ([.cluster, .suse_ai_cluster] | all(. == null or
    (type == "object" and (keys - ["instance_type_cp", "instance_type_gpu",
     "instance_type_nongpu", "num_worker_nodes_gpu", "num_worker_nodes_nongpu",
     "root_volume_size"] | length == 0))))
' >/dev/null || { printf 'Unsupported fields in node configuration: %s\n' "${config}" >&2; exit 2; }

nodes="$(yq eval-all -o=json 'select(fileIndex == 0) * select(fileIndex == 1)' \
  "${lab_dir}/nodes.example.yml" "${config}")"
jq -e '
  def integer: type == "number" and . == floor;
  [.cluster, .suse_ai_cluster] | all(
    ([.num_worker_nodes_gpu, .num_worker_nodes_nongpu] | all(integer and . >= 0)) and
    (.root_volume_size | integer and . >= 80) and
    ([.instance_type_cp, .instance_type_gpu, .instance_type_nongpu] |
      all(type == "string" and test("^[a-z][a-z0-9-]*\\.[a-z0-9]+$"))) and
    ([.instance_type_cp, .instance_type_nongpu] | all(test("^[gp][0-9]") | not)) and
    (.num_worker_nodes_gpu == 0 or (.instance_type_gpu | test("^(g4dn|g5|g6|g6e|p4d|p4de|p5|p5e|p5en)\\."))))
' <<<"${nodes}" >/dev/null || {
  printf 'Invalid node sizes/counts; GPU workers require a supported x86_64 NVIDIA instance family (see nodes.example.yml).\n' >&2
  exit 2
}
jq -e '
  (.gpu_operator_chart_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.enable_time_slicing | type == "boolean") and
  (.time_slicing_replicas | type == "number" and . == floor and . >= 1)
' <<<"${nodes}" >/dev/null || { printf 'Invalid GPU Operator version or time-slicing configuration.\n' >&2; exit 2; }

jq -S '
  (.cluster.num_worker_nodes_gpu + .suse_ai_cluster.num_worker_nodes_gpu > 0) as $gpu |
  .airgap_lab_node_config = true |
  .enable_gpu_operator = $gpu |
  .enable_nvidia_driver_pkg_install = $gpu |
  .use_nvidia_driver_installer = false
' <<<"${nodes}"
