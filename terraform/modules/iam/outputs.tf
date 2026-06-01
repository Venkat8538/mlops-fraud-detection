output "eks_cluster_role_arn" {
  description = "IAM role ARN for EKS cluster"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_nodes_role_arn" {
  description = "IAM role ARN for EKS worker nodes"
  value       = aws_iam_role.eks_nodes.arn
}

output "eks_nodes_role_name" {
  description = "IAM role name for EKS worker nodes"
  value       = aws_iam_role.eks_nodes.name
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}

output "mlflow_role_arn" {
  description = "IRSA role ARN for MLflow"
  value       = aws_iam_role.mlflow.arn
}

output "jupyterhub_role_arn" {
  description = "IRSA role ARN for JupyterHub"
  value       = aws_iam_role.jupyterhub.arn
}

output "aws_lb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "ebs_csi_driver_role_arn" {
  description = "IRSA role ARN for EBS CSI Driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "efs_csi_driver_role_arn" {
  description = "IRSA role ARN for EFS CSI Driver"
  value       = aws_iam_role.efs_csi_driver.arn
}
