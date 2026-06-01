output "cross_account_role_arn" {
  description = "Paste this into Databricks: Settings → Workspace admin → Cloud Resources → Credentials"
  value       = aws_iam_role.databricks_cross_account.arn
}

output "instance_profile_arn" {
  description = "Paste this into Databricks: Settings → Workspace admin → Cloud Resources → Instance profiles"
  value       = aws_iam_instance_profile.databricks.arn
}

output "cloud_storage_role_arn" {
  description = "Unity Catalog storage credential role ARN — already registered in Databricks Catalog → Credentials"
  value       = aws_iam_role.databricks_cloud_storage.arn
}
