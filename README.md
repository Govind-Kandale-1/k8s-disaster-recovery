# Feature: Restore Runbook Automation

Bash scripts and operational runbooks for restoring Kubernetes workloads and RDS databases from Velero backups. Covers full cluster restore, single namespace restore, post-restore validation, and step-by-step operator runbooks.

## Scripts

```
scripts/restore/
├── restore-cluster.sh     # Full cluster restore with validation
├── restore-namespace.sh   # Single namespace targeted restore
└── validate-restore.sh    # Post-restore health checks

runbooks/
├── full-cluster-restore.md   # 6-step DR procedure with RTO targets
└── rds-restore.md            # RDS snapshot restore + secret update
```

## restore-cluster.sh

Full cluster restore from any completed Velero backup.

```bash
# Dry run first — validates backup exists without restoring
./scripts/restore/restore-cluster.sh \
  --backup daily-full-backup-20240601020000 \
  --cluster devops-dr \
  --region us-west-2 \
  --dry-run

# Live restore
./scripts/restore/restore-cluster.sh \
  --backup daily-full-backup-20240601020000 \
  --cluster devops-dr \
  --region us-west-2
```

The script:
1. Switches `kubectl` context to the DR cluster
2. Verifies Velero is running and the backup is `Completed`
3. Creates a Velero restore and polls until done
4. Automatically runs `validate-restore.sh`

## restore-namespace.sh

Restore a single namespace without touching the rest of the cluster — useful for recovering from accidental deletion or corruption of one team's namespace.

```bash
./scripts/restore/restore-namespace.sh \
  --backup hourly-namespace-backup-20240601110000 \
  --namespace app

# Dry run
./scripts/restore/restore-namespace.sh \
  --backup hourly-namespace-backup-20240601110000 \
  --namespace app \
  --dry-run
```

## validate-restore.sh

Runs automatically after a restore. Can also be run standalone at any time.

```bash
# Validate specific namespaces and health endpoints
VALIDATE_NAMESPACES="app monitoring" \
HEALTH_ENDPOINTS="http://<alb-dns>/api/health" \
./scripts/restore/validate-restore.sh
```

Checks performed:
- All Deployments have the expected number of ready replicas
- All PVCs are in `Bound` state
- HTTP health endpoints return `200`
- No failed/partially-failed Velero restores in the cluster

Exit code `0` = all checks passed. Exit code `1` = one or more checks failed.

## Runbooks

### Full Cluster Restore (`runbooks/full-cluster-restore.md`)

Step-by-step operator guide for a full region failover:
1. Declare incident and assign roles
2. Identify latest good backup
3. Run `restore-cluster.sh`
4. Restore RDS from DR snapshot (parallel)
5. Run validation
6. Update DNS to point to DR ALB

**RTO target:** 30 minutes (prod critical)

### RDS Restore (`runbooks/rds-restore.md`)

Commands to list DR snapshots, restore to a new RDS instance, and update the Kubernetes secret with the new endpoint.

## Prerequisites

- `velero` CLI installed and configured against target cluster
- `kubectl` with access to the DR cluster
- `aws` CLI configured for both primary and DR regions
- Velero installed in DR cluster pointing to DR S3 bucket
