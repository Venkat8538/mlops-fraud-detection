variable "name" {
  description = "Prefix for all IAM resource names"
  type        = string
}

# ── OIDC (populated after EKS cluster is created) ──────────────────────────
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN — used to scope IRSA assume-role policies"
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without https:// prefix"
  type        = string
  default     = ""
}

# ── Namespace overrides ────────────────────────────────────────────────────
variable "external_secrets_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator runs"
  type        = string
  default     = "external-secrets"
}

variable "mlflow_namespace" {
  description = "Kubernetes namespace where MLflow runs"
  type        = string
  default     = "mlflow"
}

variable "jupyterhub_namespace" {
  description = "Kubernetes namespace where JupyterHub runs"
  type        = string
  default     = "jupyterhub"
}

# ── KMS key ARNs ───────────────────────────────────────────────────────────
variable "ebs_kms_key_arn" {
  description = "KMS key ARN for EBS volumes"
  type        = string
}

variable "s3_kms_key_arn" {
  description = "KMS key ARN for S3 buckets"
  type        = string
}

variable "secrets_manager_kms_key_arn" {
  description = "KMS key ARN for Secrets Manager"
  type        = string
}

# ── S3 bucket names ────────────────────────────────────────────────────────
variable "artifact_bucket_name" {
  description = "Name of the MLflow artifact S3 bucket"
  type        = string
}

variable "production_bucket_name" {
  description = "Name of the production data S3 bucket"
  type        = string
}

variable "tags" {
  description = "Tags applied to all IAM resources"
  type        = map(string)
  default     = {}
}
