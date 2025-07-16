data "aws_ami" "aws_ami_sle_micro_mgmt" {
  count = var.cluster["image_distro"] == "sle-micro" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]

  filter {
    name   = "name"
    values = ["suse-${var.cluster["image_distro"]}-${replace(var.cluster["image_distro_version"], ".", "-")}-byos-v*-hvm-ssd-${var.cluster["image_arch"]}"]
  }
}

data "aws_ami" "aws_ami_sles_mgmt" {
  count = var.cluster["image_distro"] == "sles" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]
  name_regex       = "^suse-${var.cluster["image_distro"]}-${var.cluster["image_distro_version"]}-v\\d+-hvm-ssd-${var.cluster["image_arch"]}"
}

locals {
  ami_id_mgmt = var.cluster["image_distro"] == "sle-micro" ? data.aws_ami.aws_ami_sle_micro_mgmt[0].id : data.aws_ami.aws_ami_sles_mgmt[0].id
}


data "aws_ami" "aws_ami_sle_micro_suse_ai" {
  count = try(length(var.suse_ai_cluster["image_distro"]), 0) > 0 && var.suse_ai_cluster["image_distro"] == "sle-micro" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]

  filter {
    name   = "name"
    values = ["suse-${var.suse_ai_cluster["image_distro"]}-${replace(var.suse_ai_cluster["image_distro_version"], ".", "-")}-byos-v*-hvm-ssd-${var.suse_ai_cluster["image_arch"]}"]
  }
}

data "aws_ami" "aws_ami_sles_suse_ai" {
  count = try(length(var.suse_ai_cluster["image_distro"]), 0) > 0 && var.suse_ai_cluster["image_distro"] == "sles" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]
  name_regex       = "^suse-${var.suse_ai_cluster["image_distro"]}-${var.suse_ai_cluster["image_distro_version"]}-v\\d+-hvm-ssd-${var.suse_ai_cluster["image_arch"]}"
}


locals {
  suse_ai_value_map = {
    "slemicro-ami-id-suse-ai" = var.suse_ai_cluster["image_distro"] == "sle-micro" ? data.aws_ami.aws_ami_sle_micro_suse_ai[0].id : local.ami_id_mgmt
    "sles-ami-id-suse-ai" = var.suse_ai_cluster["image_distro"] == "sles" ? data.aws_ami.aws_ami_sles_suse_ai[0].id : local.ami_id_mgmt
  }
  ami_id_suse_ai = var.suse_ai_cluster["image_distro"] == "sle-micro" ? local.suse_ai_value_map["slemicro-ami-id-suse-ai"] : local.suse_ai_value_map["sles-ami-id-suse-ai"]
}


data "aws_ami" "aws_ami_sle_micro_suse_observability_cluster" {
  count = try(length(var.suse_observability_cluster["image_distro"]), 0) > 0 && var.suse_observability_cluster["image_distro"] == "sle-micro" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]

  filter {
    name   = "name"
    values = ["suse-${var.suse_observability_cluster["image_distro"]}-${replace(var.suse_observability_cluster["image_distro_version"], ".", "-")}-byos-v*-hvm-ssd-${var.suse_observability_cluster["image_arch"]}"]
  }
}

data "aws_ami" "aws_ami_sles_suse_observability_cluster" {
  count = try(length(var.suse_observability_cluster["image_distro"]), 0) > 0 && var.suse_observability_cluster["image_distro"] == "sles" ? 1 : 0
  most_recent      = true
  owners           = [var.aws["image_ami_account_number"]]
  name_regex       = "^suse-${var.suse_observability_cluster["image_distro"]}-${var.suse_observability_cluster["image_distro_version"]}-v\\d+-hvm-ssd-${var.suse_observability_cluster["image_arch"]}"
}


locals {
  suse_observability_value_map = {
    "slemicro-ami-id-suse-observability-cluster" = var.suse_observability_cluster["image_distro"] == "sle-micro" ? data.aws_ami.aws_ami_sle_micro_suse_observability_cluster[0].id : local.ami_id_mgmt
    "sles-ami-id-suse-observability-cluster" = var.suse_observability_cluster["image_distro"] == "sles" ? data.aws_ami.aws_ami_sles_suse_observability_cluster[0].id : local.ami_id_mgmt
  }
  ami_id_suse_observability = var.suse_observability_cluster["image_distro"] == "sle-micro" ? local.suse_observability_value_map["slemicro-ami-id-suse-observability-cluster"] : local.suse_observability_value_map["sles-ami-id-suse-observability-cluster"]
}