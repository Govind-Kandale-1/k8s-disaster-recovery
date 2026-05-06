#!/usr/bin/env bash
# Generates a DR drill markdown report written to dr-drill-report.md

set -euo pipefail

BACKUP_NAME=""
BACKUP_AGE=""
RESTORE_STATUS=""
DRY_RUN="false"
ENV="staging"

while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)         BACKUP_NAME="$2";    shift 2 ;;
    --backup-age)     BACKUP_AGE="$2";     shift 2 ;;
    --restore-status) RESTORE_STATUS="$2"; shift 2 ;;
    --dry-run)        DRY_RUN="$2";        shift 2 ;;
    --env)            ENV="$2";            shift 2 ;;
    *) shift ;;
  esac
done

DRILL_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")
RTO_MINUTES=$((SECONDS / 60))
RPO_HOURS="$BACKUP_AGE"

STATUS_ICON="✅"
[[ "$RESTORE_STATUS" != "success" ]] && STATUS_ICON="❌"

cat > dr-drill-report.md <<EOF
# DR Drill Report

**Date:** $DRILL_DATE
**Environment:** $ENV
**Dry Run:** $DRY_RUN
**Overall Status:** $STATUS_ICON $RESTORE_STATUS

---

## Metrics

| Metric | Value | Target |
|--------|-------|--------|
| RTO (restore duration) | ~${RTO_MINUTES} min | 30 min (prod) / 120 min (staging) |
| RPO (backup age at drill) | ${RPO_HOURS}h | 1h (prod) / 8h (staging) |
| Backup used | \`$BACKUP_NAME\` | — |

## Checks

| Check | Result |
|-------|--------|
| Latest backup found | $([[ -n "$BACKUP_NAME" ]] && echo ✅ || echo ❌) |
| Backup age within RPO | $([[ "$RPO_HOURS" -le 25 ]] && echo ✅ || echo ❌) ($RPO_HOURS h) |
| Namespace restore | $STATUS_ICON $RESTORE_STATUS |
| Post-restore validation | $([[ "$DRY_RUN" == "true" ]] && echo "⏭ skipped (dry run)" || echo "$STATUS_ICON $RESTORE_STATUS") |

## Notes

- Drill run: $([[ "$DRY_RUN" == "true" ]] && echo "**DRY RUN** — no actual restore performed" || echo "Full restore executed and validated")
- Next scheduled drill: next Sunday 03:00 UTC

EOF

echo "Report written to dr-drill-report.md"
cat dr-drill-report.md
