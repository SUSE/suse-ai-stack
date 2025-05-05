variable "aws" {
  type = object({
    access_key = string #AWS access key
    secret_key = string #AWS secret key
    region = string  #AWS region to launch resources
    az1 = string  #AWS availability zone 1 for the aws_region
    az2 = string #AWS availability zone 2 for the aws_region
    resource_owner = string #email address associated with aws account
    resource_prefix = string #prefix to uniquely identity resources
    key_pair_name = string # your aws keypair name. It must be created for the given AWS region
    key_pair_public_key = string #the public portiin of your aws keypair
    image_ami_account_number = string #the aws owner of the image
  })
}

variable "cluster" {
  type = object({
    user = string
    user_home = string
    root_volume_size = string
    image_arch = string
    image_distro = string
    image_distro_version = string
    instance_type_cp = string #Instance type for control plane nodes
    instance_type_gpu = string #Instance type for worker nodes with GPU
    instance_type_nongpu = string #Instance type for worker nodes with no GPU
    num_cp_nodes = string #Number of control plane nodes including the master node
    num_worker_nodes_gpu = string #Number of worker nodes with gpu instance type
    num_worker_nodes_nongpu = string #Number of worker nodes with no gpu instance type
    token = string #The RKE2 Cluster Join Token to use for the cluster(s)
    version = string #The RKE2 Version to use for the clusters(s)
  })
  default = {
    user = "ec2-user"
    user_home = "/home/ec2-user"
    root_volume_size = 350
    image_arch = "x86_64"
    image_distro = "sle-micro"
    image_distro_version = "6.0"
    instance_type_cp = "g4dn.2xlarge" #g4dn has GPU
    instance_type_gpu = "g4dn.2xlarge" #g4dn has GPU
    instance_type_nongpu = "m5d.2xlarge"
    num_cp_nodes = 1
    num_worker_nodes_gpu = 0
    num_worker_nodes_nongpu = 0
    token = "ai-rke2token"
    version = "v1.32.4+rke2r1"
  }
}
