# Feature: RDS Snapshot Automation

Automatically copies RDS automated snapshots to the DR region via a Lambda function triggered by EventBridge. Old DR copies are pruned on a rolling retention window, keeping storage costs under control.

## How It Works

```
RDS automated snapshot completes (us-east-1)
        │
        ▼
EventBridge rule (RDS-EVENT-0002)
        │
        ▼
Lambda: rds-snapshot-copy
  ├── Copies snapshot to us-west-2 with KMS encryption
  ├── Tags copy with CopiedFrom, CopiedAt, ManagedBy
  └── Deletes DR copies older than RETENTION_DAYS
```

## Components

```
lambda/rds-snapshot-copy/
└── handler.py          # Python 3.12 Lambda — copy + cleanup logic

terraform/modules/rds-backup/
├── main.tf             # Lambda, CloudWatch log group, EventBridge rule + target,
│                       # Lambda permission, RDS backup window config
├── variables.tf
└── outputs.tf
```

## Prerequisites

- RDS instances with automated backups enabled
- Terraform >= 1.5.0, Python 3.12 available for packaging
- AWS credentials with `rds:*`, `lambda:*`, and `events:*` permissions

## Deploy

```bash
cd terraform/environments/primary
terraform apply \
  -var="db_instance_ids=[\"devops-dev-db\",\"devops-prod-db\"]"
```

Terraform will:
1. Package `lambda/rds-snapshot-copy/handler.py` into a ZIP
2. Create the Lambda with `SOURCE_REGION`, `DR_REGION`, `RETENTION_DAYS` env vars
3. Create a CloudWatch EventBridge rule filtering on `RDS-EVENT-0002` for the specified instance IDs
4. Grant EventBridge permission to invoke the Lambda
5. Set `backup_window` and `backup_retention_period` on each RDS instance

## Verify

After a snapshot completes, check Lambda logs:

```bash
aws logs tail /aws/lambda/rds-snapshot-copy-<env> --follow
```

List DR copies:

```bash
aws rds describe-db-snapshots \
  --region us-west-2 \
  --query "DBSnapshots[?TagList[?Key=='ManagedBy'&&Value=='dr-automation']].[DBSnapshotIdentifier,SnapshotCreateTime,Status]" \
  --output table
```

## Module Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Deployment environment | — |
| `aws_region` | Source (primary) AWS region | — |
| `dr_region` | DR AWS region | `us-west-2` |
| `db_instance_ids` | List of RDS instance IDs to watch | — |
| `retention_days` | Days to keep DR snapshot copies | `30` |
| `dr_kms_key_id` | KMS key for DR snapshot encryption | `alias/aws/rds` |
| `backup_window` | RDS preferred backup window (UTC) | `02:00-03:00` |
| `backup_retention` | RDS automated backup retention days | `7` |

## Module Outputs

| Output | Description |
|--------|-------------|
| `lambda_function_arn` | Lambda function ARN |
| `lambda_function_name` | Lambda function name |
| `eventbridge_rule_arn` | EventBridge rule ARN |
