variable "source_bucket_arn" {
  description = "ARN of the primary Velero S3 bucket"
  type        = string
}

variable "source_bucket_id" {
  type = string
}

variable "destination_bucket_name" {
  description = "Name of the DR-region replica bucket"
  type        = string
}

variable "destination_region" {
  type    = string
  default = "us-west-2"
}

variable "source_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type = string
}

variable "backup_retention_days" {
  type    = number
  default = 30
}
