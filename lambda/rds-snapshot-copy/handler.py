"""
RDS cross-region snapshot copy.

Triggered by EventBridge when a automated RDS snapshot completes.
Copies the snapshot to the DR region and cleans up snapshots older
than RETENTION_DAYS.
"""

import os
import boto3
import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SOURCE_REGION = os.environ["SOURCE_REGION"]
DR_REGION     = os.environ["DR_REGION"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "30"))
KMS_KEY_ID     = os.environ.get("DR_KMS_KEY_ID", "alias/aws/rds")

source_client = boto3.client("rds", region_name=SOURCE_REGION)
dr_client     = boto3.client("rds", region_name=DR_REGION)


def lambda_handler(event, context):
    detail = event.get("detail", {})
    source_id  = detail.get("SourceIdentifier")
    source_arn = detail.get("SourceArn")
    event_id   = detail.get("EventID", "")

    # Only act on automated snapshot completion
    if "RDS-EVENT-0002" not in event_id:
        logger.info("Ignoring event %s for %s", event_id, source_id)
        return

    logger.info("Copying snapshot %s to %s", source_id, DR_REGION)
    copy_snapshot(source_id, source_arn)
    cleanup_old_snapshots(source_id.split(":")[-1])


def copy_snapshot(source_id: str, source_arn: str):
    timestamp  = datetime.now(timezone.utc).strftime("%Y%m%d%H%M")
    target_id  = f"dr-copy-{source_id[-30:]}-{timestamp}"

    resp = dr_client.copy_db_snapshot(
        SourceDBSnapshotIdentifier=source_arn,
        TargetDBSnapshotIdentifier=target_id,
        SourceRegion=SOURCE_REGION,
        KmsKeyId=KMS_KEY_ID,
        CopyTags=True,
        Tags=[
            {"Key": "CopiedFrom",   "Value": SOURCE_REGION},
            {"Key": "CopiedAt",     "Value": timestamp},
            {"Key": "ManagedBy",    "Value": "dr-automation"},
        ],
    )
    logger.info("Copy initiated: %s", resp["DBSnapshot"]["DBSnapshotIdentifier"])


def cleanup_old_snapshots(db_id: str):
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)

    paginator = dr_client.get_paginator("describe_db_snapshots")
    for page in paginator.paginate(DBInstanceIdentifier=db_id, SnapshotType="manual"):
        for snap in page["DBSnapshots"]:
            # Only delete copies managed by this automation
            tags = {t["Key"]: t["Value"] for t in snap.get("TagList", [])}
            if tags.get("ManagedBy") != "dr-automation":
                continue

            created_at = snap["SnapshotCreateTime"]
            if created_at < cutoff:
                logger.info("Deleting old DR snapshot: %s (created %s)",
                            snap["DBSnapshotIdentifier"], created_at.date())
                dr_client.delete_db_snapshot(
                    DBSnapshotIdentifier=snap["DBSnapshotIdentifier"]
                )
