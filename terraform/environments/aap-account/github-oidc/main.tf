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
# GitHub OIDC Identity Provider
# Allows GitHub Actions to authenticate with AWS
# without storing any long-lived credentials
# ──────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = { Name = "github-actions-oidc", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# IAM Role — GitHub Actions MLOps
# Only trusts pushes to main branch of our repo
# ──────────────────────────────────────────────
resource "aws_iam_role" "github_actions" {
  name = "github-actions-mlops-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Allow main branch and PRs from this specific repo only
          "token.actions.githubusercontent.com:sub" = "repo:Venkat8538/mlops-fraud-detection:*"
        }
      }
    }]
  })

  tags = { Name = "github-actions-mlops-role", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Permissions — what GitHub Actions can do
# ──────────────────────────────────────────────

# S3 — upload training code + read/write MLflow store
resource "aws_iam_role_policy" "github_actions_s3" {
  name = "github-actions-s3-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerCodeUpload"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
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

# SageMaker — launch training jobs
resource "aws_iam_role_policy" "github_actions_sagemaker" {
  name = "github-actions-sagemaker-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerTraining"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:StopTrainingJob",
          "sagemaker:ListTrainingJobs"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassSageMakerRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::482227257362:role/sagemaker-execution-role"
      },
      {
        Sid    = "SSMRunCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:WaitForCommandExecuted",
          "ssm:GetParameter"
        ]
        Resource = "*"
      }
    ]
  })
}

# Terraform state — read/write for terraform workflow
resource "aws_iam_role_policy" "github_actions_terraform" {
  name = "github-actions-terraform-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::mlops-dev-tf-state",
          "arn:aws:s3:::mlops-dev-tf-state/*"
        ]
      },
      {
        Sid    = "TerraformLockTable"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:us-east-1:482227257362:table/mlops-dev-tfstate-lock"
      },
      {
        Sid    = "TerraformIAMS3"
        Effect = "Allow"
        Action = [
          "iam:*",
          "s3:*",
          "ec2:Describe*",
          "kms:Describe*",
          "kms:List*"
        ]
        Resource = "*"
      }
    ]
  })
}
