output "sagemaker_role_arn" {
  description = "Paste into 04_sagemaker_training.py as role_arn"
  value       = aws_iam_role.sagemaker.arn
}
