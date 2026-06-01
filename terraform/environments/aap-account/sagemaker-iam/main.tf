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

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────
# SageMaker Execution Role
# Used by SageMaker training jobs and endpoints
# ──────────────────────────────────────────────
resource "aws_iam_role" "sagemaker" {
  name = "sagemaker-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "sagemaker-execution-role", ManagedBy = "Terraform" }
}

# AWS managed policy — covers most SageMaker operations
resource "aws_iam_role_policy_attachment" "sagemaker_full" {
  role       = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# S3 access — read Gold features, write model artifacts
resource "aws_iam_role_policy" "sagemaker_s3" {
  name = "sagemaker-s3-policy"
  role = aws_iam_role.sagemaker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GoldBucketRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::mlops-dev-gold",
          "arn:aws:s3:::mlops-dev-gold/*"
        ]
      },
      {
        Sid    = "MLflowStoreFull"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::mlops-dev-mlflow-store",
          "arn:aws:s3:::mlops-dev-mlflow-store/*"
        ]
      }
    ]
  })
}

# ECR access — pull training container images
resource "aws_iam_role_policy_attachment" "sagemaker_ecr" {
  role       = aws_iam_role.sagemaker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
