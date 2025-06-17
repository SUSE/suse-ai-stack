# Launch the first server node
resource "aws_instance" "suse_observability_cp_master" {
  #checking for one of the values inside suse_observability_cluster is not null or empty
  count = var.suse_observability_cluster["user"] != null && var.suse_observability_cluster["user"] != "" ? 1 : 0
  depends_on = [aws_internet_gateway.igw]
  ami           		= local.ami_id_suse_observability
  instance_type 		= var.suse_observability_cluster["instance_type_cp"] != null ? var.suse_observability_cluster["instance_type_cp"] : "g4dn.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.suse_observability_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-observability-cp0"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Launch the additional server nodes
resource "aws_instance" "suse_observability_cp_other" {
  count = var.suse_observability_cluster["num_cp_nodes"] != null ? var.suse_observability_cluster["num_cp_nodes"] - 1 : 0
  depends_on = [aws_instance.cp_master ]
  ami           		= local.ami_id_suse_observability
  instance_type 		= var.suse_observability_cluster["instance_type_cp"] != null ? var.suse_observability_cluster["instance_type_cp"] : "g4dn.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.suse_observability_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-observability-cp${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}


# Launch the agent nodes
resource "aws_instance" "suse_observability_worker" {
  count = var.suse_observability_cluster["num_worker_nodes"] != null ? var.suse_observability_cluster["num_worker_nodes"] : 0
  depends_on = [aws_instance.cp_other ]
  ami           		= local.ami_id_suse_observability
  instance_type 		= var.suse_observability_cluster["instance_type_worker"] != null ? var.suse_observability_cluster["instance_type_worker"] : "m5d.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  root_block_device {
    volume_size = var.suse_observability_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-observability-worker-${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Instance Types
data "aws_ec2_instance_type" "suse_observability_cp" {
  count = length(aws_instance.suse_observability_cp_master) > 0 ? 1 : 0
  instance_type  = try(aws_instance.suse_observability_cp_master[0].instance_type, "g4dn.2xlarge")
}

data "aws_ec2_instance_type" "suse_observability_worker" {
  count = var.suse_observability_cluster["num_worker_nodes"] != null ? var.suse_observability_cluster["num_worker_nodes"] : 0
  instance_type = aws_instance.suse_observability_worker[0].instance_type
}

data "aws_instance" "suse_observability_cp_master" {
  count = length(aws_instance.suse_observability_cp_master) > 0 ? 1 : 0
  instance_id = try(aws_instance.suse_observability_cp_master[0].id, null)
}

data "aws_instance" "suse_observability_cp_other" {
  count = try(var.suse_observability_cluster["num_cp_nodes"]-1, 0)
  instance_id = aws_instance.suse_observability_cp_other[count.index].id
}

data "aws_instance" "suse_observability_worker" {
  count = var.suse_observability_cluster["num_worker_nodes"] != null ? var.suse_observability_cluster["num_worker_nodes"] : 0
  instance_id = aws_instance.suse_observability_worker[count.index].id
}
