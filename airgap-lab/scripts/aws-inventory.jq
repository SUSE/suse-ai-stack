# Input: OpenTofu output -json. Names match roles/vm/tasks/*_cluster_output.yml.
def ips($key): .[$key].value // [];
def hosts($ips; $prefix; $server):
  $ips | to_entries | map({key: ($prefix + ((.key + 1) | tostring)),
    value: {ansible_host: .value, airgap_cluster_server: $server}}) | from_entries;
hosts(ips("instance_public_ip_worker_gpu"); "mgmt-rancher-wkrgpu"; "mgmt-rancher") as $mgpu |
hosts(ips("suse_ai_instance_public_ip_worker_gpu"); "suse-ai-wkrgpu"; "suse-ai") as $dgpu |
hosts(ips("instance_public_ip_worker_nongpu"); "mgmt-rancher-wkr"; "mgmt-rancher") as $mcpu |
hosts(ips("suse_ai_instance_public_ip_worker_nongpu"); "suse-ai-wkr"; "suse-ai") as $dcpu |
hosts(ips("mgmt_instance_public_ip_cp_other"); "mgmt-rancher-cp"; "mgmt-rancher") as $mcp |
hosts(ips("suse_ai_instance_public_ip_cp_other"); "suse-ai-cp"; "suse-ai") as $dcp |
{
  all: {
    vars: {
      ansible_user: $user, ansible_become: true,
      ansible_ssh_private_key_file: $key,
      ansible_ssh_common_args: "-o StrictHostKeyChecking=accept-new"
    },
    children: {
      aif_management: {hosts: {"mgmt-rancher": {
        ansible_host: .mgmt_instance_public_ip.value,
        airgap_gpu_nodes: ($mgpu | keys)
      }}},
      aif_workloads: {hosts: {"suse-ai": {
        ansible_host: .suse_ai_instance_public_ip.value,
        airgap_gpu_nodes: ($dgpu | keys)
      }}},
      aif_workers: {hosts: ($mgpu + $dgpu + $mcpu + $dcpu)},
      aif_gpu_workers: {hosts: ($mgpu + $dgpu)},
      aif_other_servers: {hosts: ($mcp + $dcp)},
      airgap_services: {hosts: {"airgap-services": {ansible_host: .airgap_services_public_ip.value}}},
      rke2_servers: {hosts: {"airgap-services": {}}},
      rke2_airgap_nodes: {children: {aif_management: {}, aif_workloads: {}, aif_workers: {}, aif_other_servers: {}}},
      airgap_clients: {hosts: {}},
      airgap_isolated: {children: {rke2_airgap_nodes: {}, airgap_clients: {}}}
    }
  }
}
