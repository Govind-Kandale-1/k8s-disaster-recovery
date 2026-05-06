# RDS Restore Runbook

**RPO target:** 1 hour (automated snapshots every hour)
**RTO target:** 20 minutes for RDS restore

## List DR Snapshots

```bash
aws rds describe-db-snapshots \
  --region us-west-2 \
  --query "DBSnapshots[?contains(DBSnapshotIdentifier,'dr-copy')].[DBSnapshotIdentifier,SnapshotCreateTime,Status]" \
  --output table | sort -k2 | tail -20
```

## Restore to New Instance

```bash
SNAPSHOT_ID="dr-copy-<original-id>-<timestamp>"
NEW_DB_ID="restored-db-$(date +%Y%m%d)"

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$NEW_DB_ID" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-instance-class db.t3.medium \
  --vpc-security-group-ids <sg-id> \
  --db-subnet-group-name <subnet-group> \
  --region us-west-2 \
  --no-multi-az \
  --no-publicly-accessible

# Wait (typically 10-15 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier "$NEW_DB_ID" \
  --region us-west-2

# Get endpoint
aws rds describe-db-instances \
  --db-instance-identifier "$NEW_DB_ID" \
  --region us-west-2 \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

## Update Application Secret

```bash
# Update Kubernetes secret with new DB endpoint
kubectl -n app create secret generic db-credentials \
  --from-literal=uri="mysql://admin:<pass>@<new-endpoint>:3306/appdb" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl -n app rollout restart deployment/app
kubectl -n app rollout status deployment/app
```
