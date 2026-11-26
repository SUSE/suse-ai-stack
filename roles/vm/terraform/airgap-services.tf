resource "aws_security_group" "airgap_services" {
  count       = try(var.airgap_services.enabled, false) ? 1 : 0
  name        = "${var.aws["resource_prefix"]}-aif-airgap-services"
  description = "Gated Harbor and Gitea services for the AIF air-gap QA lab"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from the lab controller only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.airgap_services.controller_cidr]
  }

  ingress {
    description = "Harbor HTTPS from the private lab VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Gitea HTTP baseline from the private lab VPC"
    from_port   = 30030
    to_port     = 30030
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.aws["resource_prefix"]}-aif-airgap-services"
    Owner   = var.aws["resource_owner"]
    Project = "aif-airgap"
  }
}

resource "aws_instance" "airgap_services" {
  count                       = try(var.airgap_services.enabled, false) ? 1 : 0
  depends_on                  = [aws_internet_gateway.igw]
  ami                         = local.ami_id_mgmt
  instance_type               = var.airgap_services.instance_type
  key_name                    = var.aws["key_pair_name"]
  vpc_security_group_ids      = [aws_security_group.airgap_services[0].id]
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.subnet1.id

  user_data = <<-EOF
    #!/bin/bash
    sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
  EOF

  root_block_device {
    volume_size = var.airgap_services.root_volume_size
  }

  tags = {
    Name    = "${var.aws["resource_prefix"]}-aif-airgap-services"
    Owner   = var.aws["resource_owner"]
    Project = "aif-airgap"
  }
}
