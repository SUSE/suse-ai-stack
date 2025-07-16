#https://docs.rke2.io/install/ha#1-configure-the-fixed-registration-address
#A layer 4 (TCP) load balancer

#creating nlb - rke2
resource "aws_lb" "suse_ai_rke2" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name                             = "${var.aws["resource_prefix"]}-ai-rke2-lb"
  internal                         = false
  load_balancer_type               = "network"
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false
  subnets                          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  security_groups                  = [aws_security_group.sg.id]
}

#create target group - rke2
resource "aws_lb_target_group" "suse_ai_rke2_targetgroup1" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name        = "${aws_lb.suse_ai_rke2[0].name}-tg1"
  port        = 9345
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group" "suse_ai_rke2_targetgroup2" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name        = "${aws_lb.suse_ai_rke2[0].name}-tg2"
  port        = 6443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_listener" "suse_ai_rke2_listener1" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  load_balancer_arn = aws_lb.suse_ai_rke2[0].arn
  protocol          = "TCP"
  port              = 9345
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup1[0].arn
  }
}

resource "aws_lb_listener" "suse_ai_rke2_listener2" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  load_balancer_arn = aws_lb.suse_ai_rke2[0].arn
  protocol          = "TCP"
  port              = 6443
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup2[0].arn
  }
}

resource "aws_lb_target_group_attachment" "suse_ai_rke2_tg_attachment1_cp_master" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup1[0].arn
  target_id        = aws_instance.suse_ai_cp_master[0].id
}

resource "aws_lb_target_group_attachment" "suse_ai_rke2_tg_attachment1_cp_others" {
  count      = var.suse_ai_cluster["num_cp_nodes"] != null ? var.suse_ai_cluster["num_cp_nodes"] - 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup1[0].arn
  target_id  = aws_instance.suse_ai_cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_rke2_tg_attachment2_cp_master" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup2[0].arn
  target_id        = aws_instance.suse_ai_cp_master[0].id
}

resource "aws_lb_target_group_attachment" "suse_ai_rke2_tg_attachment2_cp_others" {
  count      = var.suse_ai_cluster["num_cp_nodes"] != null ? var.suse_ai_cluster["num_cp_nodes"] - 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_rke2_targetgroup2[0].arn
  target_id  = aws_instance.suse_ai_cp_other[count.index].id
}

#data "aws_lb" "suse_ai_rke2" {
#  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
#  name = aws_lb.suse_ai_rke2[0].name
#}

data "aws_lb" "suse_ai_rke2" {
  count = length(aws_lb.suse_ai_rke2) > 0 ? 1 : 0
  name  = try(aws_lb.suse_ai_rke2[0].name, null)
}


#creating nlb - ingress
resource "aws_lb" "suse_ai_ingress" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name                             = "${var.aws["resource_prefix"]}-ai-ingress-lb"
  internal                         = false
  load_balancer_type               = "network"
  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = false
  subnets                          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  security_groups                  = [aws_security_group.sg.id]
}

#create target group - ingress
resource "aws_lb_target_group" "suse_ai_ingress_targetgroup1" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name        = "${aws_lb.suse_ai_ingress[0].name}-tg1"

  port        = 443
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_target_group" "suse_ai_ingress_targetgroup2" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  name        = "${aws_lb.suse_ai_ingress[0].name}-tg2"

  port        = 80
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id
}


resource "aws_lb_listener" "suse_ai_ingress_listener1" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  load_balancer_arn = aws_lb.suse_ai_ingress[0].arn
  protocol          = "TCP"
  port              = 443
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup1[0].arn
  }
}

resource "aws_lb_listener" "suse_ai_ingress_listener2" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  load_balancer_arn = aws_lb.suse_ai_ingress[0].arn
  protocol          = "TCP"
  port              = 80
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup2[0].arn
  }
}

# Attach all suse_ai_cluster control plane nodes and worker nodes to ingress target groups
resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment1_suse_ai_cp_master" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup1[0].arn
  target_id        = aws_instance.suse_ai_cp_master[0].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment1_suse_ai_cp_others" {
  count      = var.suse_ai_cluster["num_cp_nodes"] != null ? var.suse_ai_cluster["num_cp_nodes"] - 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup1[0].arn
  target_id   = aws_instance.suse_ai_cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment2_suse_ai_cp_master" {
  count = var.suse_ai_cluster["user"] != null && var.suse_ai_cluster["user"] != "" ? 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup2[0].arn
  target_id        = aws_instance.suse_ai_cp_master[0].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment2_suse_ai_cp_others" {
  count      = var.suse_ai_cluster["num_cp_nodes"] != null ? var.suse_ai_cluster["num_cp_nodes"] - 1 : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup2[0].arn
  target_id   = aws_instance.suse_ai_cp_other[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment1_suse_ai_worker_gpu" {
  count      = var.suse_ai_cluster["num_worker_nodes_gpu"] != null ? var.suse_ai_cluster["num_worker_nodes_gpu"] : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup1[0].arn
  target_id   = aws_instance.suse_ai_worker_gpu[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment2_suse_ai_worker_gpu" {
  count      = var.suse_ai_cluster["num_worker_nodes_gpu"] != null ? var.suse_ai_cluster["num_worker_nodes_gpu"] : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup2[0].arn
  target_id   = aws_instance.suse_ai_worker_gpu[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment1_suse_ai_worker_nongpu" {
  count      = var.suse_ai_cluster["num_worker_nodes_nongpu"] != null ? var.suse_ai_cluster["num_worker_nodes_nongpu"] : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup1[0].arn
  target_id   = aws_instance.suse_ai_worker_nongpu[count.index].id
}

resource "aws_lb_target_group_attachment" "suse_ai_ingress_tg_attachment2_suse_ai_worker_nongpu" {
  count      = var.suse_ai_cluster["num_worker_nodes_nongpu"] != null ? var.suse_ai_cluster["num_worker_nodes_nongpu"] : 0
  target_group_arn = aws_lb_target_group.suse_ai_ingress_targetgroup2[0].arn
  target_id   = aws_instance.suse_ai_worker_nongpu[count.index].id
}


#data "aws_lb" "suse_ai_ingress" {
#  name = aws_lb.suse_ai_ingress[0].name
#}

data "aws_lb" "suse_ai_ingress" {
  count = length(aws_lb.suse_ai_ingress) > 0 ? 1 : 0
  name  = try(aws_lb.suse_ai_ingress[0].name, null)
}
