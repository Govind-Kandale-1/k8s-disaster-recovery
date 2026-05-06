#!/usr/bin/env bash
# Restore a single namespace from a Velero backup.
# Usage: ./restore-namespace.sh --backup <name> --namespace <ns> [--dry-run]

set -euo pipefail

BACKUP_NAME=""
NAMESPACE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)    BACKUP_NAME="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2";   shift 2 ;;
    --dry-run)   DRY_RUN=true;     shift ;;
    *) echo "Usage: $0 --backup <name> --namespace <ns> [--dry-run]"; exit 1 ;;
  esac
done

[[ -z "$BACKUP_NAME" || -z "$NAMESPACE" ]] && { echo "--backup and --namespace are required"; exit 1; }

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
fail() { echo "[$(date -u +%H:%M:%S)] FAIL: $*" >&2; exit 1; }

RESTORE_NAME="ns-restore-${NAMESPACE}-$(date +%Y%m%d%H%M)"

log "Restoring namespace '$NAMESPACE' from backup '$BACKUP_NAME'..."

STATUS=$(velero backup describe "$BACKUP_NAME" 2>/dev/null | grep "Phase:" | awk '{print $2}')
[[ "$STATUS" != "Completed" ]] && fail "Backup not in Completed state: $STATUS"

if $DRY_RUN; then
  log "DRY RUN — would run: velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME --include-namespaces $NAMESPACE"
  exit 0
fi

velero restore create "$RESTORE_NAME" \
  --from-backup "$BACKUP_NAME" \
  --include-namespaces "$NAMESPACE" \
  --wait

log "Checking pod status in $NAMESPACE..."
kubectl -n "$NAMESPACE" wait --for=condition=ready pod --all --timeout=180s \
  || log "WARN: Some pods not ready yet — check manually"

log "=== Namespace restore complete: $RESTORE_NAME ==="
