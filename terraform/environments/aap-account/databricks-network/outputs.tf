output "vpc_id" {
  value = aws_vpc.databricks.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_id" {
  value = aws_security_group.databricks.id
}
