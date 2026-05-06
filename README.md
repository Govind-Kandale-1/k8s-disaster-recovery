# Feature: S3 Cross-Region Replication

Automatically replicates every Velero backup object from the primary S3 bucket (`us-east-1`) to a DR replica bucket (`us-west-2`) using S3 Cross-Region Replication (CRR). Backups are available in the DR region within seconds of being written.

## Architecture

```
us-east-1 (primary)                    us-west-2 (DR)
┌────────────────────────┐              ┌────────────────────────┐
│ velero-backups-primary │ ──── CRR ──► │ velero-backups-dr      │
│ (STANDARD)             │              │ (STANDARD_IA)          │
│ Versioning: enabled    │              │ Versioning: enabled    │
│ SSE: AES256            │              │ SSE: AES256            │
└────────────────────────┘              └────────────────────────┘
         ▲
   IAM replication role
   (assumed by S3 service)
```

`STANDARD_IA` is used in the DR bucket to reduce storage costs — DR backups are accessed rarely (only during actual recovery).

## Components

runbooks/
├── full-cluster-restore.md   # 6-step DR procedure with RTO targets
└── rds-restore.md            # RDS snapshot restore + secret update
```
terraform/modules/s3-replication/
├── main.tf        # Replica bucket, IAM role, replication config on source bucket
├── variables.tf
└── outputs.tf

terraform/environments/dr/
└── main.tf        # DR environment — reads primary state via remote_state
```

## Prerequisites

- `feature/velero-backup-setup` applied first (provides source bucket ARN/ID)
- Terraform remote state for `dr/primary` accessible
- AWS credentials with permissions in both `us-east-1` and `us-west-2`

## Deploy

```bash
cd terraform/environments/dr
terraform init
terraform apply
```

Terraform reads the primary environment's remote state to obtain the source bucket ARN and ID automatically — no manual wiring needed.

## Verify Replication

After applying, upload a test object to the primary bucket and confirm it appears in the replica within ~60 seconds:

```bash
echo "test" | aws s3 cp - s3://<primary-bucket>/replication-test.txt
aws s3 ls s3://<dr-bucket>/ --region us-west-2 | grep replication-test
```

Check replication metrics in the AWS console under **S3 → Management → Replication metrics**.

## Module Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `source_bucket_arn` | ARN of the primary Velero bucket | — |
| `source_bucket_id` | ID of the primary Velero bucket | — |
| `destination_bucket_name` | Name for the DR replica bucket | — |
| `destination_region` | DR AWS region | `us-west-2` |
| `source_region` | Primary AWS region | `us-east-1` |
| `backup_retention_days` | Lifecycle expiry on replica bucket | `30` |

## Module Outputs

| Output | Description |
|--------|-------------|
| `replica_bucket_arn` | DR replica bucket ARN |
| `replica_bucket_id` | DR replica bucket name |
| `replication_role_arn` | IAM role ARN used by S3 CRR |
