terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "dr/dr-region/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock-table"
  }
  required_providers {
    aws        = { source = "hashicorp/aws",       version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
    helm       = { source = "hashicorp/helm",       version = "~> 2.13" }
  }
}

# Primary region — needed to apply replication config on source bucket
provider "aws" {
  alias  = "primary"
  region = "us-east-1"
}

# DR region
provider "aws" {
  region = "us-west-2"
}

data "terraform_remote_state" "primary" {
  backend = "s3"
  config = {
    bucket = "your-tf-state-bucket"
    key    = "dr/primary/terraform.tfstate"
    region = "us-east-1"
  }
}

module "s3_replication" {
  source = "../../modules/s3-replication"

  environment             = "dr"
  source_bucket_arn       = data.terraform_remote_state.primary.outputs.velero_bucket_arn
  source_bucket_id        = data.terraform_remote_state.primary.outputs.velero_bucket_id
  destination_bucket_name = "velero-backups-dr-${data.aws_caller_identity.current.account_id}"
  source_region           = "us-east-1"
  destination_region      = "us-west-2"
  backup_retention_days   = 30

  providers = {
    aws    = aws
    aws.dr = aws
  }
}

data "aws_caller_identity" "current" {}
