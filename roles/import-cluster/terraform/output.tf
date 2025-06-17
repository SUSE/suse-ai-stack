output "kubectl_command" {
  value = "${rancher2_cluster.generic_cluster.cluster_registration_token.0.command}"
}

output "insecure_kubectl_command" {
  value = "${rancher2_cluster.generic_cluster.cluster_registration_token.0.insecure_command}"
}

