# Feature: RTO/RPO Monitoring Dashboard

Prometheus alerting rules and a Grafana dashboard that give real-time visibility into backup health, RPO exposure, and storage availability. Alerts fire before an RPO breach becomes a real incident.

## Components

runbooks/
├── full-cluster-restore.md   # 6-step DR procedure with RTO targets
└── rds-restore.md            # RDS snapshot restore + secret update
```
kubernetes/monitoring/
├── velero-servicemonitor.yaml   # Scrapes Velero /metrics every 30s
└── backup-alerts.yaml           # 6 PrometheusRules for DR health

monitoring/grafana/
└── dr-dashboard.json            # Grafana dashboard — 7 panels
```

## Alerts

| Alert | Severity | Condition | Action |
|-------|----------|-----------|--------|
| `VeleroBackupRPOBreach` | critical | Hourly backup not completed in >2h | Check Velero logs, trigger manual backup |
| `VeleroDailyBackupMissing` | warning | Daily full backup not completed in >25h | Inspect schedule, check S3 connectivity |
| `VeleroBackupFailed` | critical | Any backup failure counter > 0 | `kubectl -n velero get backups` |
| `VeleroBackupPartialFailure` | warning | Partial failure counter > 0 | Check which resources failed to backup |
| `VeleroBackupStorageUnavailable` | critical | S3 storage location unreachable | Check S3 bucket policy and network connectivity |
| `VeleroControllerDown` | critical | Velero pod not running | Check pod status in `velero` namespace |

All critical alerts link to the restore runbook in their annotations.

## Grafana Dashboard Panels

| Panel | Type | What it shows |
|-------|------|---------------|
| Time Since Last Successful Backup | Stat (red >2h) | RPO exposure per schedule |
| Backup Success Rate (24h) | Stat (red <99%) | Overall backup reliability |
| Storage Location Status | Stat | S3 available / unavailable |
| Backup Duration by Schedule | Timeseries | How long each backup takes |
| Backup Size by Schedule | Timeseries | Storage growth trend |
| Backup Failures (24h) | Timeseries | Failure spikes |
| Total Backups in Storage | Timeseries | Retention window health |

## Prerequisites

- `kube-prometheus-stack` Helm release installed with label `release: kube-prometheus-stack`
- Velero installed with `metrics.enabled: true` and `metrics.serviceMonitor.enabled: true`
- Grafana accessible (via port-forward or ingress)

## Deploy

```bash
# Apply ServiceMonitor and alert rules
kubectl apply -f kubernetes/monitoring/velero-servicemonitor.yaml
kubectl apply -f kubernetes/monitoring/backup-alerts.yaml

# Import Grafana dashboard
# In Grafana UI: Dashboards → Import → Upload dr-dashboard.json
```

Or if using the `kube-prometheus-stack` Helm release, add the dashboard via `grafana.dashboards`:

```yaml
grafana:
  dashboards:
    default:
      dr-dashboard:
        url: https://raw.githubusercontent.com/Govind-Kandale-1/k8s-disaster-recovery/feature/rto-rpo-monitoring-dashboard/monitoring/grafana/dr-dashboard.json
```

## Verify Alerts Are Loaded

```bash
kubectl -n monitoring get prometheusrule dr-backup-alerts
kubectl -n monitoring get servicemonitor velero
```

Check Prometheus has picked up the rules:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090
# Open http://localhost:9090/rules and search for "velero"
```
