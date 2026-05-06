#!/usr/bin/env bash
# Full cluster restore from a Velero backup.
# Usage: ./restore-cluster.sh --backup <name> --cluster <eks-cluster> --region <aws-region>

set -euo pipefail

BACKUP_NAME=""
DR_CLUSTER=""
DR_REGION="us-west-2"
DRY_RUN=false
TIMEOUT=600

usage() {
  echo "Usage: $0 --backup <velero-backup-name> --cluster <eks-cluster-name> --region <aws-region> [--dry-run]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)  BACKUP_NAME="$2"; shift 2 ;;
    --cluster) DR_CLUSTER="$2";  shift 2 ;;
    --region)  DR_REGION="$2";   shift 2 ;;
    --dry-run) DRY_RUN=true;     shift ;;
    *) usage ;;
  esac
done

[[ -z "$BACKUP_NAME" || -z "$DR_CLUSTER" ]] && usage

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
warn() { echo "[$(date -u +%H:%M:%S)] WARN: $*" >&2; }
fail() { echo "[$(date -u +%H:%M:%S)] FAIL: $*" >&2; exit 1; }

log "=== DR Cluster Restore ==="
log "Backup  : $BACKUP_NAME"
log "Cluster : $DR_CLUSTER ($DR_REGION)"
log "Dry-run : $DRY_RUN"

# ── 1. Switch kubectl context to DR cluster ───────────────────────────────────
log "Configuring kubectl for DR cluster..."
aws eks update-kubeconfig --name "$DR_CLUSTER" --region "$DR_REGION"

# ── 2. Verify Velero is running in DR cluster ─────────────────────────────────
log "Checking Velero installation..."
kubectl -n velero wait --for=condition=ready pod -l app.kubernetes.io/name=velero --timeout=60s \
  || fail "Velero not ready in DR cluster. Run: helm install velero ..."

# ── 3. Verify the backup exists and is Complete ───────────────────────────────
log "Verifying backup '$BACKUP_NAME'..."
STATUS=$(velero backup describe "$BACKUP_NAME" --details 2>/dev/null \
  | grep "Phase:" | awk '{print $2}' || echo "NotFound")

[[ "$STATUS" != "Completed" ]] && fail "Backup '$BACKUP_NAME' status is '$STATUS' — cannot restore."

# ── 4. Execute restore ────────────────────────────────────────────────────────
RESTORE_NAME="restore-${BACKUP_NAME}-$(date +%Y%m%d%H%M)"

if $DRY_RUN; then
  log "DRY RUN — would run: velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME"
else
  log "Creating restore '$RESTORE_NAME'..."
  velero restore create "$RESTORE_NAME" \
    --from-backup "$BACKUP_NAME" \
    --wait \
    --timeout "${TIMEOUT}s"
fi

# ── 5. Wait and validate ──────────────────────────────────────────────────────
if ! $DRY_RUN; then
  log "Waiting for restore to complete..."
  for i in $(seq 1 $((TIMEOUT / 10))); do
    PHASE=$(velero restore describe "$RESTORE_NAME" 2>/dev/null | grep "Phase:" | awk '{print $2}')
    [[ "$PHASE" == "Completed" ]] && break
    [[ "$PHASE" == "Failed" || "$PHASE" == "PartiallyFailed" ]] && \
      fail "Restore ended with phase: $PHASE. Check: velero restore describe $RESTORE_NAME"
    sleep 10
  done

  log "Running post-restore validation..."
  bash "$(dirname "$0")/validate-restore.sh"
fi

log "=== Restore complete: $RESTORE_NAME ==="
