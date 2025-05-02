output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.cp_master.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance master"
  value       = aws_instance.cp_master.public_ip
}

output "instance_public_ip_cp_other" {
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

output "kubeapi_fqdn" {
  value = data.aws_lb.rke2.dns_name
  description = "RKE2 endpoint"
}

output "ingress_fqdn" {
  value = data.aws_lb.ingress.dns_name
  description = "Ingress LB endpoint"
}

output "ami_id" {
  description = "ami id"
  value       = local.ami_id
}
