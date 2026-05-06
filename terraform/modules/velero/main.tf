terraform {
  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes",  version = "~> 2.27" }
    helm       = { source = "hashicorp/helm",        version = "~> 2.13" }
  }
}

data "aws_caller_identity" "current" {}

# ── S3 bucket for Velero backups ──────────────────────────────────────────────

resource "aws_s3_bucket" "velero" {
  bucket        = "velero-backups-${var.environment}-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment != "prod"

  tags = {
    Name        = "velero-backups-${var.environment}"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = var.backup_retention_days }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
}

# ── IRSA — IAM role for Velero pods ──────────────────────────────────────────

data "aws_iam_policy_document" "velero_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${var.eks_oidc_provider}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider}:sub"
      values   = ["system:serviceaccount:velero:velero"]
    }
  }
}

data "aws_iam_policy_document" "velero_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
      "s3:ListBucket", "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = [
      aws_s3_bucket.velero.arn,
      "${aws_s3_bucket.velero.arn}/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateSnapshot", "ec2:DeleteSnapshot",
      "ec2:DescribeSnapshots", "ec2:DescribeVolumes",
      "ec2:CreateTags", "ec2:DescribeTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "velero" {
  name               = "velero-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.velero_assume.json
  tags               = { Environment = var.environment }
}

resource "aws_iam_role_policy" "velero" {
  name   = "velero-s3-ec2-${var.environment}"
  role   = aws_iam_role.velero.id
  policy = data.aws_iam_policy_document.velero_s3.json
}

# ── Namespace ─────────────────────────────────────────────────────────────────

resource "kubernetes_namespace" "velero" {
  metadata {
    name = "velero"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

# ── Velero Helm release ───────────────────────────────────────────────────────

resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = var.velero_version
  namespace  = kubernetes_namespace.velero.metadata[0].name

  set { name = "image.tag";                   value = var.velero_image_tag }
  set { name = "configuration.backupStorageLocation[0].provider"; value = "aws" }
  set { name = "configuration.backupStorageLocation[0].bucket";   value = aws_s3_bucket.velero.id }
  set { name = "configuration.backupStorageLocation[0].config.region"; value = var.aws_region }
  set { name = "configuration.volumeSnapshotLocation[0].provider"; value = "aws" }
  set { name = "configuration.volumeSnapshotLocation[0].config.region"; value = var.aws_region }
  set { name = "serviceAccount.server.annotations.eks\\.amazonaws\\.com/role-arn"; value = aws_iam_role.velero.arn }
  set { name = "initContainers[0].name";  value = "velero-plugin-for-aws" }
  set { name = "initContainers[0].image"; value = "velero/velero-plugin-for-aws:v1.9.0" }
  set { name = "initContainers[0].volumeMounts[0].mountPath"; value = "/target" }
  set { name = "initContainers[0].volumeMounts[0].name";      value = "plugins" }
  set { name = "metrics.enabled";         value = "true" }
  set { name = "metrics.serviceMonitor.enabled"; value = "true" }

  depends_on = [kubernetes_namespace.velero]
}
