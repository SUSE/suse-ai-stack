terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.00"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  	= var.aws["region"]
  access_key	= var.aws["access_key"]
  secret_key	= var.aws["secret_key"]
}

