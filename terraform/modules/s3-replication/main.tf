terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# DR-region provider — alias used only in this module
provider "aws" {
  alias  = "dr"
  region = var.destination_region
}

data "aws_caller_identity" "current" {}

# ── Replica bucket (DR region) ────────────────────────────────────────────────

resource "aws_s3_bucket" "replica" {
  provider      = aws.dr
  bucket        = var.destination_bucket_name
  force_destroy = var.environment != "prod"

  tags = {
    Name        = var.destination_bucket_name
    Environment = var.environment
    Role        = "velero-dr-replica"
  }
}

resource "aws_s3_bucket_versioning" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "replica" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "replica" {
  provider = aws.dr
  bucket   = aws_s3_bucket.replica.id

  rule {
    id     = "expire-replicated-backups"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = var.backup_retention_days }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
}

# ── IAM role for S3 replication ───────────────────────────────────────────────

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replication_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [var.source_bucket_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${var.source_bucket_arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.replica.arn}/*"]
  }
}

resource "aws_iam_role" "replication" {
  name               = "s3-velero-replication-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

resource "aws_iam_role_policy" "replication" {
  name   = "s3-velero-replication-${var.environment}"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication_policy.json
}

# ── Replication configuration on source bucket ────────────────────────────────

resource "aws_s3_bucket_replication_configuration" "velero" {
  bucket = var.source_bucket_id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all-backups"
    status = "Enabled"

    filter { prefix = "" }

    delete_marker_replication { status = "Enabled" }

    destination {
      bucket        = aws_s3_bucket.replica.arn
      storage_class = "STANDARD_IA"  # cheaper for DR cold storage

      encryption_configuration {
        replica_kms_key_id = "aws/s3"
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.replica]
}
