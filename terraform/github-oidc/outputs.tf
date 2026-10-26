output "aws_account_id" {
  description = "AWS account in which the OIDC resources were created."
  value       = data.aws_caller_identity.current.account_id
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  value       = aws_iam_role.github_actions.name
}

output "github_actions_role_arn" {
  description = "ARN to register as the AWS_ROLE_ARN GitHub Actions variable."
  value       = aws_iam_role.github_actions.arn
}
