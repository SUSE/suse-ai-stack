#https://docs.rke2.io/install/ha#1-configure-the-fixed-registration-address
#A layer 4 (TCP) load balancer

#creating nlb - rke2
resource "aws_lb" "rke2" {
  name                             = "${var.aws["resource_prefix"]}-dev-ai-k8s-lb"
  internal                         = false
  load_balancer_type               = "network"
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false
  subnets                          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  security_groups                  = [aws_security_group.sg.id]
}

#create target group - rke2
resource "aws_lb_target_group" "rke2_targetgroup1" {
  name        = "${aws_lb.rke2.name}-tg1"
  port        = 9345
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group" "rke2_targetgroup2" {
  name        = "${aws_lb.rke2.name}-tg2"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_listener" "rke2_listener1" {
  load_balancer_arn = aws_lb.rke2.arn
  protocol          = "TCP"
  port              = 9345
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rke2_targetgroup1.arn
  }
}

resource "aws_lb_listener" "rke2_listener2" {
  load_balancer_arn = aws_lb.rke2.arn
  protocol          = "TCP"
  port              = 6443
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rke2_targetgroup2.arn
  }
}

resource "aws_lb_target_group_attachment" "rke2_tg_attachment1_cp_master" {
  target_group_arn = aws_lb_target_group.rke2_targetgroup1.arn
  target_id        = aws_instance.cp_master.id
}

resource "aws_lb_target_group_attachment" "rke2_tg_attachment1_cp_others" {
  target_group_arn = aws_lb_target_group.rke2_targetgroup1.arn
  count      = var.cluster["num_cp_nodes"] - 1
  target_id  = aws_instance.cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "rke2_tg_attachment2_cp_master" {
  target_group_arn = aws_lb_target_group.rke2_targetgroup2.arn
  target_id        = aws_instance.cp_master.id
}

resource "aws_lb_target_group_attachment" "rke2_tg_attachment2_cp_others" {
  target_group_arn = aws_lb_target_group.rke2_targetgroup2.arn
  count      = var.cluster["num_cp_nodes"] - 1
  target_id  = aws_instance.cp_other[count.index].id
}


#creating nlb - ingress
resource "aws_lb" "ingress" {
  name                             = "${var.aws["resource_prefix"]}-dev-ai-ingress-lb"
  internal                         = false
  load_balancer_type               = "network"
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false
  subnets                          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  security_groups                  = [aws_security_group.sg.id]
}

#create target group - ingress
resource "aws_lb_target_group" "ingress_targetgroup1" {
  name        = "${aws_lb.ingress.name}-tg1"

  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group" "ingress_targetgroup2" {
  name        = "${aws_lb.ingress.name}-tg2"

  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}


resource "aws_lb_listener" "ingress_listener1" {
  load_balancer_arn = aws_lb.ingress.arn
  protocol          = "TCP"
  port              = 443
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_targetgroup1.arn
  }
}

resource "aws_lb_listener" "ingress_listener2" {
  load_balancer_arn = aws_lb.ingress.arn
  protocol          = "TCP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_targetgroup2.arn
  }
}

# Attach all control plane nodes and worker nodes to ingress target groups
resource "aws_lb_target_group_attachment" "ingress_tg_attachment1_cp_master" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup1.arn
  target_id        = aws_instance.cp_master.id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment1_cp_others" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup1.arn
  count      = var.cluster["num_cp_nodes"] - 1
  target_id   = aws_instance.cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment2_cp_master" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup2.arn
  target_id        = aws_instance.cp_master.id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment2_cp_others" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup2.arn
  count      = var.cluster["num_cp_nodes"] - 1
  target_id   = aws_instance.cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment1_worker_gpu" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup1.arn
  count      = var.cluster["num_worker_nodes_gpu"]
  target_id   = aws_instance.worker_gpu[count.index].id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment2_worker_gpu" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup2.arn
  count      = var.cluster["num_worker_nodes_gpu"]
  target_id   = aws_instance.worker_gpu[count.index].id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment1_worker_nongpu" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup1.arn
  count      = var.cluster["num_worker_nodes_nongpu"]
  target_id   = aws_instance.worker_nongpu[count.index].id
}

resource "aws_lb_target_group_attachment" "ingress_tg_attachment2_worker_nongpu" {
  target_group_arn = aws_lb_target_group.ingress_targetgroup2.arn
  count      = var.cluster["num_worker_nodes_nongpu"]
  target_id   = aws_instance.worker_nongpu[count.index].id
}

data "aws_lb" "rke2" {
  name = aws_lb.rke2.name
}

data "aws_lb" "ingress" {
  name = aws_lb.ingress.name
}