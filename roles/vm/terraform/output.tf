output "ami_id_mgmt" {
  description = "ami id"
  value       = local.ami_id_mgmt
}

output "ami_id_suse_ai" {
  description = "ami id"
  value       = local.ami_id_suse_ai
}

output "ami_id_suse_observability" {
  description = "ami id"
  value       = local.ami_id_suse_observability
}

output "mgmt_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.cp_master.id
}

output "mgmt_instance_public_ip" {
  description = "Public IP address of the EC2 instance master"
  value       = aws_instance.cp_master.public_ip
}

output "mgmt_instance_public_ip_cp_other" {
  value       = data.aws_instance.cp_other.*.public_ip
  description = "IP of the control plane instances - other"
}

output "instance_public_ip_worker_gpu" {
  value       = data.aws_instance.worker_gpu.*.public_ip
  description = "IPs of the worker instances with GPU"
}

output "instance_public_ip_worker_nongpu" {
  value       = data.aws_instance.worker_nongpu.*.public_ip
  description = "IPs of the worker instances without GPU"
}

output "mgmt_kubeapi_fqdn" {
  value = data.aws_lb.rke2.dns_name
  description = "RKE2 endpoint"
}

output "mgmt_ingress_fqdn" {
  value = data.aws_lb.ingress.dns_name
  description = "Mgmt Ingress endpoint"
}

output "suse_ai_instance_id" {
  description = "ID of the EC2 instance for SUSE AI cluster"
  value = try(aws_instance.suse_ai_cp_master[0].id, null)
}

output "suse_ai_instance_public_ip" {
  description = "Public IP address of the EC2 instance master for SUSE AI cluster"
  value       = try(aws_instance.suse_ai_cp_master[0].public_ip, null)
}

output "suse_ai_instance_public_ip_cp_other" {
  value       = data.aws_instance.suse_ai_cp_other.*.public_ip
  description = "IP of the control plane instances - other for SUSE AI cluster"
}

output "suse_ai_instance_public_ip_worker_gpu" {
  value       = data.aws_instance.suse_ai_worker_gpu.*.public_ip
  description = "IPs of the worker instances with GPU for SUSE AI cluster"
}

output "suse_ai_instance_public_ip_worker_nongpu" {
  value       = data.aws_instance.suse_ai_worker_nongpu.*.public_ip
  description = "IPs of the worker instances without GPU for SUSE AI cluster"
}

output "suse_ai_kubeapi_fqdn" {
  value = try(data.aws_lb.suse_ai_rke2[0].dns_name, null)
  description = "RKE2 endpoint for SUSE AI cluster"
}

output "suse_ai_ingress_fqdn" {
  value = try(data.aws_lb.suse_ai_ingress[0].dns_name, null)
  description = "Ingress LB endpoint for SUSE AI cluster"
}


output "suse_observability_instance_id" {
  description = "ID of the EC2 instance for SUSE Observability cluster"
  value = try(aws_instance.suse_observability_cp_master[0].id, null)
}

output "suse_observability_instance_public_ip" {
  description = "Public IP address of the EC2 instance master for SUSE Observability cluster"
  value       = try(aws_instance.suse_observability_cp_master[0].public_ip, null)
}

output "suse_observability_instance_public_ip_cp_other" {
  value       = data.aws_instance.suse_observability_cp_other.*.public_ip
  description = "IP of the control plane instances - other for SUSE Observability cluster"
}

output "suse_observability_instance_public_ip_worker" {
  value       = data.aws_instance.suse_observability_worker.*.public_ip
  description = "IPs of the worker instances for SUSE Observability cluster"
}

output "suse_observability_kubeapi_fqdn" {
  value = try(data.aws_lb.suse_observ_rke2[0].dns_name, null)
  description = "RKE2 endpoint for SUSE Observability cluster"
}

output "suse_observability_ingress_fqdn" {
  value = try(data.aws_lb.suse_observ_ingress[0].dns_name, null)
  description = "Ingress LB endpoint for SUSE Observability cluster"
}