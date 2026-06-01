output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EKS nodes, RDS, EFS)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (load balancers, NAT GWs)"
  value       = aws_subnet.public[*].id
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs (EKS control plane ENIs)"
  value       = aws_subnet.intra[*].id
}

output "eks_cluster_sg_id" {
  description = "Security group ID for EKS control plane"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "Security group ID for EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}

output "efs_sg_id" {
  description = "Security group ID for EFS mount targets"
  value       = aws_security_group.efs.id
}

output "docdb_sg_id" {
  description = "Security group ID for DocumentDB"
  value       = aws_security_group.docdb.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs (one per AZ)"
  value       = aws_nat_gateway.main[*].id
}

output "availability_zones" {
  description = "AZs used"
  value       = local.azs
}
