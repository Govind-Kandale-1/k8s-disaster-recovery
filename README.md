# Feature: Velero Backup Setup

Installs Velero into EKS with an AWS S3 backend, IRSA-based authentication, and three pre-configured backup schedules covering hourly, daily, and pre-deployment use cases.

## Components

```
terraform/modules/velero/
├── main.tf        # S3 bucket, IRSA role, Velero Helm release
├── variables.tf
└── outputs.tf

terraform/environments/primary/
└── main.tf        # Wires the module to an existing EKS cluster

kubernetes/velero/schedules/
├── hourly-namespace-backup.yaml   # app + monitoring, 7-day TTL
├── daily-full-backup.yaml         # full cluster, 30-day TTL
└── pre-deploy-backup.yaml         # paused template, triggered manually before prod deploys
```

## Prerequisites

- EKS cluster running in `us-east-1`
- Terraform >= 1.5.0
- Helm 3
- `kubectl` and `velero` CLI installed
- S3 remote state backend bootstrapped

## Deploy

```bash
cd terraform/environments/primary
terraform init
terraform apply \
  -var="cluster_name=devops-prod" \
  -var="eks_oidc_provider=oidc.eks.us-east-1.amazonaws.com/id/XXXXXXXX"
```

Terraform will:
1. Create an encrypted, versioned S3 bucket with a 30-day lifecycle rule
2. Create an IAM role (IRSA) with `s3:*` and EC2 snapshot permissions, trusted by the Velero service account
3. Install Velero via Helm with the AWS plugin and metrics enabled

## Apply Backup Schedules

```bash
kubectl apply -f kubernetes/velero/schedules/
```

Verify schedules are registered:

```bash
velero schedule get
```

## Trigger a Manual Pre-Deploy Backup

Before any production deployment, create a snapshot from the paused template:

```bash
velero backup create "pre-deploy-$(date +%Y%m%d%H%M)" \
  --from-schedule pre-deploy-hook
```

## Verify a Backup

```bash
velero backup get
velero backup describe <backup-name> --details
```

## Module Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Deployment environment | — |
| `aws_region` | AWS region | — |
| `cluster_name` | EKS cluster name | — |
| `eks_oidc_provider` | OIDC provider URL (no `https://`) | — |
| `velero_version` | Helm chart version | `6.0.0` |
| `backup_retention_days` | S3 lifecycle expiry in days | `30` |

## Module Outputs

| Output | Description |
|--------|-------------|
| `bucket_name` | Velero S3 bucket name |
| `bucket_arn` | Velero S3 bucket ARN |
| `irsa_role_arn` | IAM role ARN attached to the Velero service account |
