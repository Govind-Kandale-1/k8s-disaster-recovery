terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket         = "your-tf-state-bucket"
    key            = "dr/primary/terraform.tfstate"
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

provider "aws" { region = "us-east-1" }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.primary.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.primary.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.primary.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.primary.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    }
  }
}

data "aws_eks_cluster" "primary" { name = var.cluster_name }

data "aws_eks_cluster_auth" "primary" { name = var.cluster_name }

module "velero" {
  source = "../../modules/velero"

  environment           = "primary"
  aws_region            = "us-east-1"
  cluster_name          = var.cluster_name
  eks_oidc_provider     = var.eks_oidc_provider
  backup_retention_days = 30
}

variable "cluster_name"      { type = string }
variable "eks_oidc_provider" { type = string }
