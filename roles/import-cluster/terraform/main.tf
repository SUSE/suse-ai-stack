resource "rancher2_cloud_credential" "aws" {
    name = "aws-credentials"
    description = "AWS Credentials for EC2"
    amazonec2_credential_config {
        access_key    = var.aws["access_key"]
        secret_key    = var.aws["secret_key"]
        session_token = var.aws["session_token"]
    }
}

resource "rancher2_cluster" "generic_cluster" {
  name        = var.cluster_name
  description = "Imported Kubernetes cluster"
}

