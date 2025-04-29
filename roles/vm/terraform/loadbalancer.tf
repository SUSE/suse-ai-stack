#https://docs.rke2.io/install/ha#1-configure-the-fixed-registration-address
#A layer 4 (TCP) load balancer

# AWS Classic Loadbalancer
resource "aws_elb" "rke2" {
  connection_draining         = false
  connection_draining_timeout = 300
  cross_zone_load_balancing   = true
  desync_mitigation_mode      = "defensive"
  idle_timeout                = 60
  internal                    = false
  name                        = "${var.aws["resource_prefix"]}-ai-k8s-lb"
  security_groups             = [aws_security_group.sg.id]
  subnets                     = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  health_check {
    healthy_threshold   = 3
    interval            = 30
    target              = "TCP:6443"
    timeout             = 5
    unhealthy_threshold = 5
  }

  listener {
    instance_port     = 6443
    instance_protocol = "tcp"
    lb_port           = 6443
    lb_protocol       = "tcp"
  }
  listener {
    instance_port     = 9345
    instance_protocol = "tcp"
    lb_port           = 9345
    lb_protocol       = "tcp"
  }
  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }
  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }
}

# Attach master cp node to rke2
resource "aws_elb_attachment" "rke2_attachment1" {
  elb        = aws_elb.rke2.id
  instance   = aws_instance.cp_master.id
  depends_on = [aws_elb.rke2]
}

# Attach all other cp nodes to rke2
resource "aws_elb_attachment" "rke2_attachment2" {
  elb        = aws_elb.rke2.id
  count      = var.cluster["num_cp_nodes"] - 1
  instance   = aws_instance.cp_other[count.index].id
  depends_on = [aws_elb.rke2]
}



resource "aws_elb" "ingress" {
  connection_draining         = false
  connection_draining_timeout = 300
  cross_zone_load_balancing   = true
  desync_mitigation_mode      = "defensive"
  idle_timeout                = 60
  internal                    = false
  name                        = "${var.aws["resource_prefix"]}-ai-ingress-lb"
  security_groups             = [aws_security_group.sg.id]
  subnets                     = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

  health_check {
    healthy_threshold   = 3
    interval            = 30
    target              = "TCP:80"
    timeout             = 5
    unhealthy_threshold = 5
  }

  listener {
    instance_port     = 80
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }
  listener {
    instance_port     = 443
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }
}


# Attach all controle plane nodes and worker nodes to ingress
resource "aws_elb_attachment" "ingress_attachment1" {
  elb        = aws_elb.ingress.id
  instance   = aws_instance.cp_master.id
  depends_on = [aws_elb.ingress]
}

resource "aws_elb_attachment" "ingress_attachment2" {
  elb        = aws_elb.ingress.id
  count      = var.cluster["num_cp_nodes"] - 1
  instance   = aws_instance.cp_other[count.index].id
  depends_on = [aws_elb.ingress]
}

resource "aws_elb_attachment" "ingress_attachment3" {
  elb        = aws_elb.ingress.id
  count      = var.cluster["num_worker_nodes_gpu"]
  instance   = aws_instance.worker_gpu[count.index].id
  depends_on = [aws_elb.ingress]
}

resource "aws_elb_attachment" "ingress_attachment4" {
  elb        = aws_elb.ingress.id
  count      = var.cluster["num_worker_nodes_nongpu"]
  instance   = aws_instance.worker_nongpu[count.index].id
  depends_on = [aws_elb.ingress]
}

data "aws_elb" "rke2" {
  name = aws_elb.rke2.name
}

data "aws_elb" "ingress" {
  name = aws_elb.ingress.name
}
