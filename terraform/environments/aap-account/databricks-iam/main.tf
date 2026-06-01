terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ──────────────────────────────────────────────
# Cross-account role — fixes the AccessDenied cluster launch error
# Allows Databricks (AWS 414351767826) to launch EC2 in this account
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_cross_account" {
  name = "databricks-databricks-cross-account-role6785676"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::414351767826:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.databricks_external_id
        }
      }
    }]
  })

  tags = { Name = "databricks-cross-account-role", ManagedBy = "Terraform" }
}

resource "aws_iam_role_policy" "databricks_cross_account" {
  name = "databricks-cross-account-policy"
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
        Sid    = "ServiceLinkedRole"
        Effect = "Allow"
        Action = "iam:CreateServiceLinkedRole"
        Resource = "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
        Condition = {
          StringLike = { "iam:AWSServiceName" = "spot.amazonaws.com" }
        }
      },
      {
        Sid      = "PassInstanceProfile"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.databricks_instance_profile.arn
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Unity Catalog storage credential role
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_cloud_storage" {
  name = "databricks-databricks-cloud-storage-role678566"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Databricks control plane assumes this role
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::414351767826:root" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.databricks_external_id
          }
        }
      },
      {
        # Unity Catalog UCMasterRole — required for Unity Catalog storage credential
        Effect    = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5Z2JU6WGD",
            "arn:aws:iam::482227257362:role/databricks-databricks-cloud-storage-role678566"
          ]
        }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "44da61b7-0f9d-4b32-9aeb-49bc60fcdf83"
          }
        }
      }
    ]
  })

  tags = { Name = "databricks-cloud-storage-role", ManagedBy = "Terraform" }
}

resource "aws_iam_role_policy" "databricks_cloud_storage" {
  name = "databricks-cloud-storage-policy"
  role = aws_iam_role.databricks_cloud_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3FullAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:ReEncrypt*"
        ]
        Resource = "arn:aws:kms:us-east-1:482227257362:key/9b1a0081-a40a-4cf0-90df-f609eebe225a"
      },
      {
        Sid    = "SQSFileEvents"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:SetQueueAttributes",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage"
        ]
        Resource = "arn:aws:sqs:us-east-1:482227257362:*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Instance profile — EC2 cluster nodes
# ──────────────────────────────────────────────
resource "aws_iam_role" "databricks_instance_profile" {
  name = "databricks-instance-profile-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "databricks-instance-profile-role", ManagedBy = "Terraform" }
}

resource "aws_iam_instance_profile" "databricks" {
  name = "databricks-instance-profile"
  role = aws_iam_role.databricks_instance_profile.name
}

resource "aws_iam_role_policy" "databricks_instance_profile_s3" {
  name = "databricks-instance-profile-s3-policy"
  role = aws_iam_role.databricks_instance_profile.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3Access"
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ]
      Resource = "*"
    }]
  })
}
