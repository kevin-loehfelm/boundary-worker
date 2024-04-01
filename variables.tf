variable "prefix" {
  type        = string
  default     = "boundary"
  description = "Resource name prefix"
}

variable "boundary_cluster_url" {
  type        = string
  description = "HCP Boundary Cluster URL"
}

variable "username" {
  type        = string
  description = "HCP Boundary Username for worker configuration"
}

variable "password" {
  type        = string
  sensitive   = true
  description = "HCP Boundary Password for worker configuration user"
}

variable "ingress_worker_count" {
  type        = number
  default     = 1
  description = "Quantity of ingress workers to deploy"
}

variable "egress_worker_count" {
  type        = number
  default     = 0
  description = "Quantity of egress workers to deploy"
}

variable "aws_worker_instance_type" {
  type        = string
  default     = "t3.small"
  description = "AWS EC2 instance type for worker instances"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region"
}

variable "aws_ingress_subnet_ids" {
  type        = list(string)
  default     = []
  description = "List of AWS Subnet IDs for Ingress Workers"
}

variable "aws_egress1_subnet_ids" {
  type        = list(string)
  default     = []
  description = "List of AWS Subnet IDs for tier 1 Egress Workers"
}