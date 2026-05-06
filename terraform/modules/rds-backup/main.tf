terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

data "aws_caller_identity" "current" {}

# ── Lambda package ────────────────────────────────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/rds-snapshot-copy/handler.py"
  output_path = "${path.module}/lambda_package.zip"
}

# ── IAM role for Lambda ───────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "rds:CopyDBSnapshot",
      "rds:DescribeDBSnapshots",
      "rds:DeleteDBSnapshot",
      "rds:ListTagsForResource",
      "rds:AddTagsToResource",
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:DescribeKey"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "rds-snapshot-copy-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda" {
  name   = "rds-snapshot-copy-${var.environment}"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# ── Lambda function ───────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/rds-snapshot-copy-${var.environment}"
  retention_in_days = 30
}

resource "aws_lambda_function" "rds_snapshot_copy" {
  function_name    = "rds-snapshot-copy-${var.environment}"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda.arn
  timeout          = 300

  environment {
    variables = {
      SOURCE_REGION    = var.aws_region
      DR_REGION        = var.dr_region
      RETENTION_DAYS   = tostring(var.retention_days)
      DR_KMS_KEY_ID    = var.dr_kms_key_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── EventBridge rule — fires on automated snapshot completion ─────────────────

resource "aws_cloudwatch_event_rule" "rds_snapshot_complete" {
  name        = "rds-snapshot-complete-${var.environment}"
  description = "Fires when an RDS automated snapshot completes"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Snapshot Event"]
    detail = {
      EventID            = ["RDS-EVENT-0002"]
      SourceIdentifier   = var.db_instance_ids
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.rds_snapshot_complete.name
  arn  = aws_lambda_function.rds_snapshot_copy.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_snapshot_copy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_snapshot_complete.arn
}

# ── RDS backup window + retention on each instance ───────────────────────────

resource "aws_db_instance" "backup_config" {
  for_each = toset(var.db_instance_ids)

  # Only modifying backup settings — all other settings managed elsewhere
  identifier              = each.value
  backup_window           = var.backup_window
  backup_retention_period = var.backup_retention
  skip_final_snapshot     = false
  final_snapshot_identifier = "${each.value}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    ignore_changes = [
      # Prevent drift on attributes managed by other configs
      engine, engine_version, instance_class, allocated_storage,
      username, password, db_subnet_group_name, vpc_security_group_ids,
    ]
  }
}
