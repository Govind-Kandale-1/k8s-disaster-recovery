# k8s-disaster-recovery

Production-grade Disaster Recovery platform for Kubernetes on AWS.

## What this project covers

| Feature | Branch | Tools |
|---------|--------|-------|
| Velero backup + S3 backend | `feature/velero-backup-setup` | Velero, Helm, Terraform, IRSA |
| Cross-region S3 replication | `feature/s3-cross-region-replication` | S3 CRR, IAM, Terraform |
| RDS snapshot automation | `feature/rds-snapshot-automation` | Lambda, CloudWatch Events, Terraform |
| Restore runbook automation | `feature/restore-runbook-automation` | Bash, Velero CLI, kubectl |
| Automated DR drills | `feature/dr-drill-github-action` | GitHub Actions, k6, Bash |
| RTO/RPO monitoring dashboard | `feature/rto-rpo-monitoring-dashboard` | Prometheus, Grafana, Alertmanager |

## Architecture

```
Primary Region (us-east-1)                DR Region (us-west-2)
┌──────────────────────────┐              ┌──────────────────────────┐
│  EKS Cluster             │              │  EKS Cluster (standby)   │
│  ├── Velero              │──backups──►  │  ├── Velero              │
│  │   ├── Hourly NS backup│              │  │   └── Restore target   │
│  │   └── Daily full      │              │  └── Apps (restored)     │
│  └── Apps                │              │                          │
│                          │   S3 CRR     │                          │
│  S3 (velero-primary)     │──────────►   │  S3 (velero-dr)          │
│                          │              │                          │
│  RDS                     │──snapshots►  │  RDS (restored)          │
└──────────────────────────┘              └──────────────────────────┘
```

## RTO / RPO Targets

| Tier | RPO | RTO |
|------|-----|-----|
| Critical (prod) | 1 hour | 30 min |
| Standard (staging) | 8 hours | 2 hours |
| Dev | 24 hours | 4 hours |

## Quick Start

```bash
# 1. Bootstrap primary region
cd terraform/environments/primary
terraform init && terraform apply

# 2. Bootstrap DR region
cd terraform/environments/dr
terraform init && terraform apply

# 3. Apply Velero Kubernetes manifests
kubectl apply -f kubernetes/velero/

# 4. Trigger a manual DR drill
.github/scripts/dr-drill/run-drill.sh --env staging --dry-run
```
