output "state_bucket" {
  description = "The S3 bucket holding every environment's state."
  value       = aws_s3_bucket.state.bucket
}

output "role_arns" {
  description = "The role each GitHub Environment's jobs assume."
  value       = { for k, r in aws_iam_role.ci : k => r.arn }
}

output "environments" {
  description = "The GitHub Environments managed here."
  value       = [for e in github_repository_environment.env : e.environment]
}
