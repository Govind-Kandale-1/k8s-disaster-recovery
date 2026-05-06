#!/usr/bin/env bash
# Post-restore validation. Checks critical resources are healthy.
# Exit code 0 = pass, 1 = fail.

set -euo pipefail

NAMESPACES="${VALIDATE_NAMESPACES:-app monitoring}"
HEALTH_ENDPOINTS="${HEALTH_ENDPOINTS:-}"
PASS=true

log()  { echo "[$(date -u +%H:%M:%S)] $*"; }
ok()   { echo "[$(date -u +%H:%M:%S)] ✓ $*"; }
fail() { echo "[$(date -u +%H:%M:%S)] ✗ $*" >&2; PASS=false; }

log "=== Post-Restore Validation ==="

# ── 1. Deployments rolled out ─────────────────────────────────────────────────
for ns in $NAMESPACES; do
  log "Checking deployments in namespace: $ns"
  DEPLOYS=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
  for deploy in $DEPLOYS; do
    DESIRED=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "$READY" -ge "$DESIRED" ]]; then
      ok "Deployment $ns/$deploy: $READY/$DESIRED ready"
    else
      fail "Deployment $ns/$deploy: only $READY/$DESIRED ready"
    fi
  done
done

# ── 2. PVCs bound ─────────────────────────────────────────────────────────────
for ns in $NAMESPACES; do
  PVCS=$(kubectl get pvc -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
  for pvc in $PVCS; do
    PHASE=$(kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}')
    if [[ "$PHASE" == "Bound" ]]; then
      ok "PVC $ns/$pvc: Bound"
    else
      fail "PVC $ns/$pvc: $PHASE"
    fi
  done
done

# ── 3. Health endpoint checks ─────────────────────────────────────────────────
if [[ -n "$HEALTH_ENDPOINTS" ]]; then
  for endpoint in $HEALTH_ENDPOINTS; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$endpoint" || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
      ok "Health endpoint $endpoint: HTTP $HTTP_CODE"
    else
      fail "Health endpoint $endpoint: HTTP $HTTP_CODE"
    fi
  done
fi

# ── 4. Velero restore status ──────────────────────────────────────────────────
FAILED_RESTORES=$(velero restore get 2>/dev/null | grep -E "Failed|PartiallyFailed" | wc -l || echo 0)
if [[ "$FAILED_RESTORES" -gt 0 ]]; then
  fail "There are $FAILED_RESTORES failed/partially-failed Velero restores"
else
  ok "No failed Velero restores"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if $PASS; then
  log "=== Validation PASSED ==="
  exit 0
else
  log "=== Validation FAILED — review errors above ==="
  exit 1
fi
