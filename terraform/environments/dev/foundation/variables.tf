variable "name" {
  description = "Base name prefix for all resources (e.g. saic-aap)"
  type        = string
  default     = "mlops"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-east-1"
}

# ── Networking ─────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (2 or 3)"
  type        = number
  default     = 3
}

# ── KMS ────────────────────────────────────────────────────────────────────
variable "kms_deletion_window" {
  description = "KMS key pending deletion window in days"
  type        = number
  default     = 30
}

# ── S3 ─────────────────────────────────────────────────────────────────────
variable "force_destroy_buckets" {
  description = "Allow Terraform to destroy non-empty S3 buckets (dev only)"
  type        = bool
  default     = false
}

# ── IAM / IRSA ─────────────────────────────────────────────────────────────
# These are populated after Phase 2 EKS apply and a re-apply of foundation
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (empty until EKS cluster is created)"
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without https:// (empty until EKS cluster is created)"
  type        = string
  default     = ""
}

# ── Namespace overrides ────────────────────────────────────────────────────
variable "external_secrets_namespace" {
  type    = string
  default = "external-secrets"
}

variable "mlflow_namespace" {
  type    = string
  default = "mlflow"
}

variable "jupyterhub_namespace" {
  type    = string
  default = "jupyterhub"
}

# ── Databricks ─────────────────────────────────────────────────────────────
variable "databricks_external_id" {
  description = "ExternalId from Databricks: Settings → Workspace admin → Cloud Resources → Credentials"
  type        = string
  default     = ""
}
