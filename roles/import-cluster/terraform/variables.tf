variable "aws" {
  type = object({
    access_key = string #AWS access key
    secret_key = string #AWS secret key
    region = string  #AWS region to launch resources
  })
}

variable "rancher_url" {
    type = string
}

variable "rancher_token" {
    type = string
}

variable "cluster_name" {
  type = string
}
