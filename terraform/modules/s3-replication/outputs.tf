output "replica_bucket_arn" {
  value = aws_s3_bucket.replica.arn
}

output "replica_bucket_id" {
  value = aws_s3_bucket.replica.id
}

output "replication_role_arn" {
  value = aws_iam_role.replication.arn
}
