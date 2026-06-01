output "cross_account_role_arn" {
  description = "Register in Databricks: Settings → Workspace admin → Cloud Resources → Credentials"
  value       = aws_iam_role.databricks_cross_account.arn
}

output "cloud_storage_role_arn" {
  description = "Already registered in Databricks Catalog → Credentials (recreated with same name)"
  value       = aws_iam_role.databricks_cloud_storage.arn
}

output "instance_profile_arn" {
  description = "Register in Databricks: Settings → Workspace admin → Cloud Resources → Instance profiles"
  value       = aws_iam_instance_profile.databricks.arn
}
