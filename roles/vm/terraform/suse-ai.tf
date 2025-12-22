# Launch the first server node
resource "aws_instance" "suse_ai_cp_master" {
  #checking for one of the values inside suse_ai_cluster is not null or empty
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  depends_on = [aws_internet_gateway.igw]
  ami           		= local.ami_id_suse_ai
  instance_type 		= var.suse_ai_cluster["instance_type_cp"] != null ? var.suse_ai_cluster["instance_type_cp"] : "g4dn.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  user_data = <<-EOF
    #!/bin/bash
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  EOF
  root_block_device {
    volume_size = var.suse_ai_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-cp0"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Launch the additional server nodes
resource "aws_instance" "suse_ai_cp_other" {
  count = var.suse_ai_cluster["num_cp_nodes"] != null ? var.suse_ai_cluster["num_cp_nodes"] - 1 : 0
  depends_on = [aws_instance.cp_master ]
  ami           		= local.ami_id_suse_ai
  instance_type 		= var.suse_ai_cluster["instance_type_cp"] != null ? var.suse_ai_cluster["instance_type_cp"] : "g4dn.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  user_data = <<-EOF
    #!/bin/bash
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  EOF
  root_block_device {
    volume_size = var.suse_ai_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-cp${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}


# Launch the agent nodes with nongpu
resource "aws_instance" "suse_ai_worker_nongpu" {
  count = var.suse_ai_cluster["num_worker_nodes_nongpu"] != null ? var.suse_ai_cluster["num_worker_nodes_nongpu"] : 0
  depends_on = [aws_instance.cp_other ]
  ami           		= local.ami_id_suse_ai
  instance_type 		= var.suse_ai_cluster["instance_type_nongpu"] != null ? var.suse_ai_cluster["instance_type_nongpu"] : "m5d.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  user_data = <<-EOF
    #!/bin/bash
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  EOF
  root_block_device {
    volume_size = var.suse_ai_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-worker-nongpu-${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Launch the agent nodes with gpu
resource "aws_instance" "suse_ai_worker_gpu" {
  count = var.suse_ai_cluster["num_worker_nodes_gpu"] != null ? var.suse_ai_cluster["num_worker_nodes_gpu"] : 0
  depends_on = [aws_instance.cp_other ]
  ami           		= local.ami_id_suse_ai
  instance_type 		= var.suse_ai_cluster["instance_type_gpu"] != null ? var.suse_ai_cluster["instance_type_gpu"] : "g4dn.2xlarge"
  key_name 			= var.aws["key_pair_name"]
  vpc_security_group_ids = ["${aws_security_group.sg.id}"]
  associate_public_ip_address	= true
  user_data = <<-EOF
    #!/bin/bash
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  EOF
  root_block_device {
    volume_size = var.suse_ai_cluster["root_volume_size"]
  }
  subnet_id			= aws_subnet.subnet1.id
  tags = {
    Name = "${var.aws["resource_prefix"]}-dev-ai-worker-gpu-${count.index + 1}"
    Owner = "${var.aws["resource_owner"]}"
  }
}

# Instance Types
data "aws_ec2_instance_type" "suse_ai_cp" {
  count = length(aws_instance.suse_ai_cp_master) > 0 ? 1 : 0
  instance_type  = try(aws_instance.suse_ai_cp_master[0].instance_type, "g4dn.2xlarge")
}

data "aws_ec2_instance_type" "suse_ai_worker_gpu" {
  count = var.suse_ai_cluster["num_worker_nodes_gpu"] != null ? var.suse_ai_cluster["num_worker_nodes_gpu"] : 0
  instance_type = aws_instance.suse_ai_worker_gpu[0].instance_type
}

data "aws_ec2_instance_type" "suse_ai_worker_nongpu" {
  count = var.suse_ai_cluster["num_worker_nodes_nongpu"] != null ? var.suse_ai_cluster["num_worker_nodes_nongpu"] : 0
  instance_type = aws_instance.suse_ai_worker_nongpu[0].instance_type
}

data "aws_instance" "suse_ai_cp_master" {
  count = length(aws_instance.suse_ai_cp_master) > 0 ? 1 : 0
  instance_id = try(aws_instance.suse_ai_cp_master[0].id, null)
}

data "aws_instance" "suse_ai_cp_other" {
  count = try(var.suse_ai_cluster["num_cp_nodes"]-1, 0)
  instance_id = aws_instance.suse_ai_cp_other[count.index].id
}

data "aws_instance" "suse_ai_worker_gpu" {
  count = var.suse_ai_cluster["num_worker_nodes_gpu"] != null ? var.suse_ai_cluster["num_worker_nodes_gpu"] : 0
  instance_id = aws_instance.suse_ai_worker_gpu[count.index].id
}

data "aws_instance" "suse_ai_worker_nongpu" {
  count = var.suse_ai_cluster["num_worker_nodes_nongpu"] != null ? var.suse_ai_cluster["num_worker_nodes_nongpu"] : 0
  instance_id = aws_instance.suse_ai_worker_nongpu[count.index].id
}
