#!/usr/bin/env bash
set -euo pipefail
# Exclude credentials and unused instance types. This also migrates checkpoints
# from the original CPU lab without unnecessarily reprovisioning its nodes.
yq -o=json '.' "$1" | jq -cS '
  def nodes:
    del(.token) |
    if .num_worker_nodes_gpu == 0 then del(.instance_type_gpu) else . end |
    if .num_worker_nodes_nongpu == 0 then del(.instance_type_nongpu) else . end;
  {
    cluster: (.cluster | nodes), suse_ai_cluster: (.suse_ai_cluster | nodes),
    airgap_services, aws_region, aws_az1, aws_az2, aws_resource_prefix, aws_ssh_key_name,
    gpu: (if (.cluster.num_worker_nodes_gpu + .suse_ai_cluster.num_worker_nodes_gpu) > 0
      then {enable_gpu_operator, enable_nvidia_driver_pkg_install, use_nvidia_driver_installer,
            gpu_operator_chart_version, enable_time_slicing, time_slicing_replicas}
      else null end)
  }
' | sha256sum | awk '{print $1}'
