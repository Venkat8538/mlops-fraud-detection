data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ──────────────────────────────────────────────
# Cross-account role — Databricks control plane
# Allows Databricks (AWS account 414351767826) to
# launch and manage EC2 instances in this account
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_cross_account" {
  name = "databricks-databricks-cross-account-role6785676"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::414351767826:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.databricks_external_id
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-databricks-cross-account-role" })
}

resource "aws_iam_role_policy" "databricks_cross_account" {
  name = "${var.name}-databricks-cross-account-policy"
  role = aws_iam_role.databricks_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Management"
        Effect = "Allow"
        Action = [
          "ec2:AssociateIamInstanceProfile",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CancelSpotInstanceRequests",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeIamInstanceProfileAssociations",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeNetworkAcls",
          "ec2:DescribePrefixLists",
          "ec2:DescribeReservedInstancesOfferings",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotInstanceRequests",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeVpcs",
          "ec2:DetachVolume",
          "ec2:DisassociateIamInstanceProfile",
          "ec2:ReplaceIamInstanceProfileAssociation",
          "ec2:RequestSpotInstances",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassInstanceProfile"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.databricks_instance_profile.arn
      },
      {
        Sid    = "ServiceLinkedRole"
        Effect = "Allow"
        Action = "iam:CreateServiceLinkedRole"
        Resource = "arn:aws:iam::${local.account_id}:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = "spot.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Unity Catalog storage credential role
# Allows Unity Catalog to access S3 external locations
# Original name preserved so Databricks recognises it without reconfiguration
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_cloud_storage" {
  name = "databricks-databricks-cloud-storage-role678566"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::414351767826:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.databricks_external_id
        }
      }
    }]
  })

  tags = merge(var.tags, { Name = "databricks-cloud-storage-role678566" })
}

resource "aws_iam_role_policy" "databricks_cloud_storage" {
  name = "${var.name}-databricks-cloud-storage-policy"
  role = aws_iam_role.databricks_cloud_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StorageAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket_name}",
          "arn:aws:s3:::${var.artifact_bucket_name}/*",
          "arn:aws:s3:::${var.production_bucket_name}",
          "arn:aws:s3:::${var.production_bucket_name}/*",
          "arn:aws:s3:::${var.spark_bucket_name}",
          "arn:aws:s3:::${var.spark_bucket_name}/*"
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = var.s3_kms_key_arn
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Instance profile — attached to each EC2/cluster node
# Grants cluster nodes access to S3 + KMS
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_instance_profile" {
  name = "${var.name}-databricks-instance-profile-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-databricks-instance-profile-role" })
}

resource "aws_iam_instance_profile" "databricks" {
  name = "${var.name}-databricks-instance-profile"
  role = aws_iam_role.databricks_instance_profile.name
}

resource "aws_iam_role_policy" "databricks_s3_access" {
  name = "${var.name}-databricks-s3-policy"
  role = aws_iam_role.databricks_instance_profile.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket_name}",
          "arn:aws:s3:::${var.artifact_bucket_name}/*"
        ]
      },
      {
        Sid    = "ProductionBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.production_bucket_name}",
          "arn:aws:s3:::${var.production_bucket_name}/*"
        ]
      },
      {
        Sid    = "SparkBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.spark_bucket_name}",
          "arn:aws:s3:::${var.spark_bucket_name}/*"
        ]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = var.s3_kms_key_arn
      }
    ]
  })
}
