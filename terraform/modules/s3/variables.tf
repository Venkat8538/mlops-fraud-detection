variable "name" {
  description = "Prefix for all S3 bucket and DynamoDB table names"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN for S3 bucket server-side encryption"
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to delete non-empty buckets (set true only in dev)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
