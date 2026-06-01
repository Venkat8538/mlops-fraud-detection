variable "name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used for subnet discovery tags"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to span (2 or 3)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "cloudwatch_kms_key_arn" {
  description = "KMS key ARN for CloudWatch log group encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
