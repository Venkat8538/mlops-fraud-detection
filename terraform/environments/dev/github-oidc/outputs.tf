output "github_actions_role_arn" {
  description = "Paste this into all GitHub Actions workflows as role-to-assume"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
