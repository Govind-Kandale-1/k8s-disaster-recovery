# Feature: Automated DR Drill — GitHub Actions

A GitHub Actions workflow that runs a full DR drill every Sunday at 03:00 UTC (and on demand). It finds the latest Velero backup, asserts it meets the RPO target, performs a namespace restore in the DR cluster, validates it, cleans up, and generates a drill report posted to Slack.

## Workflow Overview

## Components

runbooks/
├── full-cluster-restore.md   # 6-step DR procedure with RTO targets
└── rds-restore.md            # RDS snapshot restore + secret update
```
.github/workflows/dr-drill.yml

identify-backup ──► restore-drill ──► measure-rto
     │                   │                │
  Find latest        Restore app     Generate report
  backup + assert    namespace in    + upload artifact
  backup age < 25h   DR cluster      + post to Slack
                     Validate
                     Cleanup
```

## Triggers

| Trigger | Schedule / Condition |
|---------|----------------------|
| Scheduled | Every Sunday 03:00 UTC |
| Manual dispatch | Any time via GitHub Actions UI |

### Manual Dispatch Inputs

| Input | Options | Default |
|-------|---------|---------|
| `environment` | `staging`, `prod` | `staging` |
| `dry_run` | `true`, `false` | `true` |

A dry run validates all steps (backup found, age within RPO) without performing an actual restore — safe to run at any time.

## Jobs

### `identify-backup`
- Connects to the primary EKS cluster
- Lists all Velero backups and finds the most recent `Completed` one
- Calculates backup age in hours
- Fails the workflow if the backup is older than 25 hours (RPO breach)

### `restore-drill`
- Connects to the DR EKS cluster
- Runs `scripts/restore/restore-namespace.sh` for the `app` namespace
- Runs `scripts/restore/validate-restore.sh` (skipped in dry-run mode)
- Cleans up the test restore after validation

### `measure-rto`
- Runs `scripts/dr-drill/generate-report.sh` to produce a markdown report
- Uploads the report as a GitHub Actions artifact (retained 90 days)
- Posts pass/fail summary to Slack (if `SLACK_WEBHOOK_URL` secret is set)

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `PRIMARY_CLUSTER_NAME` | EKS cluster name in `us-east-1` |
| `DR_CLUSTER_NAME` | EKS cluster name in `us-west-2` |
| `DR_APP_ENDPOINT` | ALB DNS for the DR cluster app (health check) |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (optional) |

## GitHub Environments

The `restore-drill` job runs in the `dr-drill-staging` or `dr-drill-prod` environment. Configure protection rules in **GitHub → Settings → Environments** to require approval before a live drill runs against production.

## Drill Report

Each run produces `dr-drill-report.md` with:
- RTO achieved (workflow duration in minutes)
- RPO exposure (backup age at drill time)
- Per-check pass/fail table
- Link to the GitHub Actions run

Reports are stored as workflow artifacts for 90 days for audit and trend tracking.

## Running a Manual Dry Run

1. Go to **Actions → DR Drill → Run workflow**
2. Select `environment: staging`, `dry_run: true`
3. Click **Run workflow**

No resources will be created or modified in the DR cluster.
