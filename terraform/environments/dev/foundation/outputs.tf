# ── KMS ────────────────────────────────────────────────────────────────────
output "kms_eks_key_arn" {
  description = "KMS key ARN — EKS envelope encryption"
  value       = module.kms.eks_key_arn
}

output "kms_s3_key_arn" {
  description = "KMS key ARN — S3 buckets"
  value       = module.kms.s3_key_arn
}

output "kms_secrets_manager_key_arn" {
  description = "KMS key ARN — Secrets Manager"
  value       = module.kms.secrets_manager_key_arn
}

output "kms_ebs_key_arn" {
  description = "KMS key ARN — EBS volumes"
  value       = module.kms.ebs_key_arn
}

output "kms_cloudwatch_key_arn" {
  description = "KMS key ARN — CloudWatch Logs"
  value       = module.kms.cloudwatch_key_arn
}

# ── Networking ─────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "vpc_cidr" {
  value = module.networking.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes, RDS, EFS"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs — load balancers, NAT GWs"
  value       = module.networking.public_subnet_ids
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs — EKS control plane ENIs"
  value       = module.networking.intra_subnet_ids
}

output "eks_cluster_sg_id" {
  value = module.networking.eks_cluster_sg_id
}

output "eks_nodes_sg_id" {
  value = module.networking.eks_nodes_sg_id
}

output "efs_sg_id" {
  value = module.networking.efs_sg_id
}

output "docdb_sg_id" {
  value = module.networking.docdb_sg_id
}

output "availability_zones" {
  value = module.networking.availability_zones
}

# ── S3 ─────────────────────────────────────────────────────────────────────
output "bronze_bucket_name" {
  description = "Bronze layer bucket — raw ingested data"
  value       = module.s3.bronze_bucket_name
}

output "silver_bucket_name" {
  description = "Silver layer bucket — cleaned data"
  value       = module.s3.silver_bucket_name
}

output "gold_bucket_name" {
  description = "Gold layer bucket — ML-ready features"
  value       = module.s3.gold_bucket_name
}

output "mlflow_bucket_name" {
  description = "MLflow artifacts bucket"
  value       = module.s3.mlflow_bucket_name
}

output "spark_bucket_name" {
  value = module.s3.spark_bucket_name
}

output "tfstate_bucket_name" {
  description = "Use this bucket for the Terraform backend after first apply"
  value       = module.s3.tfstate_bucket_name
}

output "tfstate_lock_table_name" {
  description = "Use this DynamoDB table for state locking"
  value       = module.s3.tfstate_lock_table_name
}

# ── Databricks ─────────────────────────────────────────────────────────────
output "databricks_cross_account_role_arn" {
  description = "Paste into Databricks → Settings → Workspace admin → Cloud Resources → Credentials"
  value       = module.databricks.cross_account_role_arn
}

output "databricks_instance_profile_arn" {
  description = "Paste into Databricks → Settings → Workspace admin → Cloud Resources → Instance profiles"
  value       = module.databricks.instance_profile_arn
}

# ── IAM ─────────────────────────────────────────────────────────────────────
output "eks_cluster_role_arn" {
  value = module.iam.eks_cluster_role_arn
}

output "eks_nodes_role_arn" {
  value = module.iam.eks_nodes_role_arn
}

output "external_secrets_role_arn" {
  description = "IRSA role — annotate the external-secrets ServiceAccount with this"
  value       = module.iam.external_secrets_role_arn
}

output "mlflow_role_arn" {
  description = "IRSA role — annotate the mlflow ServiceAccount with this"
  value       = module.iam.mlflow_role_arn
}

output "jupyterhub_role_arn" {
  description = "IRSA role — annotate the jupyterhub ServiceAccount with this"
  value       = module.iam.jupyterhub_role_arn
}

output "aws_lb_controller_role_arn" {
  description = "IRSA role — annotate the aws-load-balancer-controller ServiceAccount with this"
  value       = module.iam.aws_lb_controller_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "IRSA role — annotate the ebs-csi-controller ServiceAccount with this"
  value       = module.iam.ebs_csi_driver_role_arn
}

output "efs_csi_driver_role_arn" {
  description = "IRSA role — annotate the efs-csi-controller ServiceAccount with this"
  value       = module.iam.efs_csi_driver_role_arn
}
