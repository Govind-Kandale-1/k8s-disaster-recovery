output "lambda_function_arn" {
  value = aws_lambda_function.rds_snapshot_copy.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.rds_snapshot_copy.function_name
}

output "eventbridge_rule_arn" {
  value = aws_cloudwatch_event_rule.rds_snapshot_complete.arn
}
