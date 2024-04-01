terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws      = ">= 5.11.0"
    boundary = ">= 1.1.9"
  }
}

# addr is provided as a variable: var.boundary_cluster_url
# auth_method_id is derived from the cluster URL endpoint
# auth_method_login_name is provided as a variable: var.username
# auth_method_password is provided as a variable: var.password

provider "boundary" {
  addr = var.boundary_cluster_url
  # auth_method_id                  = "ampw_1234567890" # changeme
  auth_method_login_name = var.username
  auth_method_password   = var.password
}

# region is provided as a variable: var.aws_region

provider "aws" {
  region = var.aws_region
}