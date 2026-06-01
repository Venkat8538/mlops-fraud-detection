variable "name" {
  description = "Prefix for all resource names"
  type        = string
}

variable "databricks_external_id" {
  description = "ExternalId from Databricks workspace: Settings → Workspace admin → Cloud Resources"
  type        = string
}

variable "artifact_bucket_name" {
  description = "MLflow artifact S3 bucket name"
  type        = string
}

variable "production_bucket_name" {
  description = "Production data S3 bucket name"
  type        = string
}

variable "spark_bucket_name" {
  description = "Spark shuffle/temp S3 bucket name"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN used to encrypt S3 buckets"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
