terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend "s3" {
  #   bucket         = "<name>-tfstate-<account_id>"
  #   key            = "aap-account/foundation/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "<name>-tfstate-lock"
  #   encrypt        = true
  #   kms_key_id     = "<s3_kms_key_arn>"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = "MLOps"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = "SAIC"
  }
}

# ──────────────────────────────────────────────
# Phase 1a: KMS keys (no dependencies)
# ──────────────────────────────────────────────
module "kms" {
  source = "../../../modules/kms"

  name                    = "${var.name}-${var.environment}"
  deletion_window_in_days = var.kms_deletion_window
  tags                    = local.common_tags
}

# ──────────────────────────────────────────────
# Phase 1b: Networking (depends on KMS for flow logs)
# ──────────────────────────────────────────────
module "networking" {
  source = "../../../modules/networking"

  name                   = "${var.name}-${var.environment}"
  cluster_name           = "${var.name}-${var.environment}-eks"
  aws_region             = var.aws_region
  vpc_cidr               = var.vpc_cidr
  az_count               = var.az_count
  cloudwatch_kms_key_arn = module.kms.cloudwatch_key_arn
  tags                   = local.common_tags

  depends_on = [module.kms]
}

# ──────────────────────────────────────────────
# Phase 1c: S3 (depends on KMS)
# ──────────────────────────────────────────────
module "s3" {
  source = "../../../modules/s3"

  name           = "${var.name}-${var.environment}"
  s3_kms_key_arn = module.kms.s3_key_arn
  force_destroy  = var.force_destroy_buckets
  tags           = local.common_tags

  depends_on = [module.kms]
}

# ──────────────────────────────────────────────
# Phase 1d: IAM (depends on S3 for bucket names + KMS for key ARNs)
# OIDC values are empty here — populated in Phase 2 after EKS is created
# ──────────────────────────────────────────────
# ──────────────────────────────────────────────
# Phase 1e: Databricks cross-account role + instance profile
# ──────────────────────────────────────────────
module "databricks" {
  source = "../../../modules/databricks"

  name                   = "${var.name}-${var.environment}"
  databricks_external_id = var.databricks_external_id
  artifact_bucket_name   = module.s3.mlflow_bucket_name
  production_bucket_name = module.s3.gold_bucket_name
  spark_bucket_name      = module.s3.spark_bucket_name
  s3_kms_key_arn         = module.kms.s3_key_arn
  tags                   = local.common_tags

  depends_on = [module.s3, module.kms]
}

module "iam" {
  source = "../../../modules/iam"

  name = "${var.name}-${var.environment}"

  # OIDC — empty until Phase 2 EKS apply
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url

  # Namespace configuration
  external_secrets_namespace = var.external_secrets_namespace
  mlflow_namespace           = var.mlflow_namespace
  jupyterhub_namespace       = var.jupyterhub_namespace

  # KMS key ARNs
  ebs_kms_key_arn             = module.kms.ebs_key_arn
  s3_kms_key_arn              = module.kms.s3_key_arn
  secrets_manager_kms_key_arn = module.kms.secrets_manager_key_arn

  # S3 bucket names (from s3 module outputs)
  artifact_bucket_name   = module.s3.mlflow_bucket_name
  production_bucket_name = module.s3.gold_bucket_name

  tags = local.common_tags

  depends_on = [module.kms, module.s3]
}
