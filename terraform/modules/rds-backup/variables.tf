variable "environment"       { type = string }
variable "aws_region"        { type = string }
variable "dr_region"         { type = string; default = "us-west-2" }
variable "db_instance_ids"   { type = list(string); description = "RDS instance IDs to monitor" }
variable "retention_days"    { type = number; default = 30 }
variable "dr_kms_key_id"     { type = string; default = "alias/aws/rds" }
variable "lambda_zip_path"   { type = string; default = "lambda_package.zip" }
variable "backup_window"     { type = string; default = "02:00-03:00" }
variable "backup_retention"  { type = number; default = 7 }
