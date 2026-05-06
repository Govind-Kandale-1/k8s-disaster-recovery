variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "eks_oidc_provider" {
  description = "EKS OIDC provider URL without https://"
  type        = string
}

variable "velero_version" {
  type    = string
  default = "6.0.0"
}

variable "velero_image_tag" {
  type    = string
  default = "v1.13.0"
}

variable "backup_retention_days" {
  type    = number
  default = 30
}
