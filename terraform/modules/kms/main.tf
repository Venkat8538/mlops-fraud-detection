data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ──────────────────────────────────────────────
# EKS — envelope encryption for Kubernetes secrets
# ──────────────────────────────────────────────
resource "aws_kms_key" "eks" {
  description             = "${var.name} EKS secrets envelope encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootFullAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "EKSServiceAccess"
        Effect = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-eks-key" })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ──────────────────────────────────────────────
# S3 — bucket-level encryption (artifacts, model store)
# ──────────────────────────────────────────────
resource "aws_kms_key" "s3" {
  description             = "${var.name} S3 bucket encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootFullAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "S3ServiceAccess"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt"
        ]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-s3-key" })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# ──────────────────────────────────────────────
# Secrets Manager — JupyterHub secrets, DB credentials
# ──────────────────────────────────────────────
resource "aws_kms_key" "secrets_manager" {
  description             = "${var.name} Secrets Manager encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootFullAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-secrets-manager-key" })
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/${var.name}-secrets-manager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# ──────────────────────────────────────────────
# EBS — EKS node root volumes + PersistentVolumes
# ──────────────────────────────────────────────
resource "aws_kms_key" "ebs" {
  description             = "${var.name} EBS volume encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootFullAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "EBSServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
          AWS     = "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-ebs-key" })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

# ──────────────────────────────────────────────
# CloudWatch Logs — VPC flow logs, EKS control plane logs
# ──────────────────────────────────────────────
resource "aws_kms_key" "cloudwatch" {
  description             = "${var.name} CloudWatch Logs encryption"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootFullAccess"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Principal = {
          Service = "logs.${local.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${local.region}:${local.account_id}:*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-cloudwatch-key" })
}

resource "aws_kms_alias" "cloudwatch" {
  name          = "alias/${var.name}-cloudwatch"
  target_key_id = aws_kms_key.cloudwatch.key_id
}
