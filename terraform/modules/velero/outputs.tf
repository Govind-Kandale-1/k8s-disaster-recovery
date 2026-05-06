output "bucket_name" {
  value = aws_s3_bucket.velero.id
}

output "bucket_arn" {
  value = aws_s3_bucket.velero.arn
}

output "irsa_role_arn" {
  value = aws_iam_role.velero.arn
}
