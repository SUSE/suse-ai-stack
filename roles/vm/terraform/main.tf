# Launch the first server node
resource "aws_instance" "cp_master" {
  depends_on = [aws_internet_gateway.igw]
  ami           		= local.ami_id_mgmt
  instance_type 		= var.cluster["instance_type_cp"]
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-mgmt-cp0"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Launch the additional server nodes
resource "aws_instance" "cp_other" {
  count = try(var.cluster["num_cp_nodes"] - 1, 0)
  depends_on = [aws_instance.cp_master ]
  ami           		= local.ami_id_mgmt
  instance_type 		= var.cluster["instance_type_cp"]
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-mgmt-cp${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}


# Launch the agent nodes with nongpu
resource "aws_instance" "worker_nongpu" {
  count = try(var.cluster["num_worker_nodes_nongpu"], 0)
  depends_on = [aws_instance.cp_other ]
  ami           		= local.ami_id_mgmt
  instance_type 		= var.cluster["instance_type_nongpu"]
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-mgmt-worker-nongpu-${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Launch the agent nodes with gpu
resource "aws_instance" "worker_gpu" {
  count    = try(var.cluster["num_worker_nodes_gpu"], 0)
  depends_on = [aws_instance.cp_other ]
  ami           		= local.ami_id_mgmt
  instance_type 		= var.cluster["instance_type_gpu"]
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-mgmt-worker-gpu-${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Instance Types
data "aws_ec2_instance_type" "cp" {
  instance_type = var.cluster["instance_type_cp"]
}

data "aws_ec2_instance_type" "worker_gpu" {
  instance_type = var.cluster["instance_type_gpu"]
}

data "aws_ec2_instance_type" "worker_nongpu" {
  instance_type = var.cluster["instance_type_nongpu"]
}

data "aws_instance" "cp_master" {
  instance_id = aws_instance.cp_master.id
}

data "aws_instance" "cp_other" {
  count = try(var.cluster["num_cp_nodes"]-1, 0)
  instance_id = aws_instance.cp_other[count.index].id
}

data "aws_instance" "worker_gpu" {
  count = try(var.cluster["num_worker_nodes_gpu"], 0)
  instance_id = aws_instance.worker_gpu[count.index].id
}

data "aws_instance" "worker_nongpu" {
  count = try(var.cluster["num_worker_nodes_nongpu"], 0)
  instance_id = aws_instance.worker_nongpu[count.index].id
}