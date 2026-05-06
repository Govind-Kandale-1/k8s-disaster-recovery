# Full Cluster Restore Runbook

**RTO target:** 30 minutes (prod critical)
**Trigger:** Primary region EKS cluster unavailable or data corruption confirmed

## Pre-requisites

- [ ] DR EKS cluster provisioned (terraform apply in `terraform/environments/dr/`)
- [ ] Velero installed in DR cluster and pointing to DR S3 bucket
- [ ] AWS credentials with access to both regions
- [ ] `velero` CLI and `kubectl` installed locally

---

## Step 1 — Declare Incident (5 min)

1. Page on-call lead via PagerDuty / Slack `#incidents`
2. Create incident channel: `#dr-YYYYMMDD`
3. Assign roles: Incident Commander, Communications Lead, Technical Lead

---

## Step 2 — Identify Latest Good Backup (5 min)

```bash
# List available backups in DR cluster
aws eks update-kubeconfig --name <dr-cluster> --region us-west-2
velero backup get

# Identify last Completed backup before the incident
velero backup describe <backup-name> --details
```

Choose the most recent backup with `Phase: Completed`.

---

## Step 3 — Restore Cluster (15 min)

```bash
./scripts/restore/restore-cluster.sh \
  --backup <backup-name> \
  --cluster <dr-cluster-name> \
  --region us-west-2
```

The script will:
1. Switch kubectl to DR cluster
2. Verify Velero readiness
3. Verify backup status
4. Create and wait for Velero restore
5. Run `validate-restore.sh` automatically

For a dry run first:
```bash
./scripts/restore/restore-cluster.sh \
  --backup <backup-name> --cluster <dr-cluster-name> --region us-west-2 --dry-run
```

---

## Step 4 — Restore RDS (parallel with Step 3)

```bash
# List available DR snapshots
aws rds describe-db-snapshots \
  --region us-west-2 \
  --query "DBSnapshots[?TagList[?Key=='ManagedBy'&&Value=='dr-automation']].[DBSnapshotIdentifier,SnapshotCreateTime,Status]" \
  --output table

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <new-db-id> \
  --db-snapshot-identifier <snapshot-id> \
  --region us-west-2

# Wait for available
aws rds wait db-instance-available --db-instance-identifier <new-db-id> --region us-west-2
```

Update the app's `SPRING_DATA_MONGODB_URI` (or DB secret) to point to the new RDS endpoint.

---

## Step 5 — Validate (5 min)

```bash
VALIDATE_NAMESPACES="app monitoring" \
HEALTH_ENDPOINTS="http://<dr-alb-dns>/api/health" \
./scripts/restore/validate-restore.sh
```

All checks must pass before proceeding.

---

## Step 6 — DNS Failover

Update Route 53 / external DNS to point traffic to DR ALB:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://runbooks/dns-failover-change-batch.json
```

---

## Step 7 — Post-Incident

- [ ] Document timeline in incident channel
- [ ] Capture RTO achieved (target: 30 min)
- [ ] Capture RPO (time difference between incident and backup timestamp)
- [ ] Open post-mortem within 24 hours
- [ ] Update runbook if steps were unclear
