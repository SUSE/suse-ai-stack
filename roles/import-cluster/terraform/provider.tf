terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "13.1.4"
    }
  }
}

provider "rancher2" {
  api_url = var.rancher_url
  token_key = var.rancher_token
  insecure = true
}

