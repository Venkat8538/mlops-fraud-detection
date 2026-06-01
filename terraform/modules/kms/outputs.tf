output "eks_key_arn" {
  description = "KMS key ARN for EKS secrets encryption"
  value       = aws_kms_key.eks.arn
}

output "eks_key_id" {
  value = aws_kms_key.eks.key_id
}

output "s3_key_arn" {
  description = "KMS key ARN for S3 bucket encryption"
  value       = aws_kms_key.s3.arn
}

output "s3_key_id" {
  value = aws_kms_key.s3.key_id
}

output "secrets_manager_key_arn" {
  description = "KMS key ARN for Secrets Manager"
  value       = aws_kms_key.secrets_manager.arn
}

output "secrets_manager_key_id" {
  value = aws_kms_key.secrets_manager.key_id
}

output "ebs_key_arn" {
  description = "KMS key ARN for EBS volumes"
  value       = aws_kms_key.ebs.arn
}

output "ebs_key_id" {
  value = aws_kms_key.ebs.key_id
}

output "cloudwatch_key_arn" {
  description = "KMS key ARN for CloudWatch Logs"
  value       = aws_kms_key.cloudwatch.arn
}

output "cloudwatch_key_id" {
  value = aws_kms_key.cloudwatch.key_id
}
