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
# Latest Amazon Linux 2023 AMI
# ──────────────────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  # Exclude ECS-optimized AMIs
  filter {
    name   = "description"
    values = ["Amazon Linux 2023 AMI*"]
  }
}

# ──────────────────────────────────────────────
# SSH Key Pair
# ──────────────────────────────────────────────
resource "aws_key_pair" "airflow" {
  key_name   = "airflow-ec2-key"
  public_key = var.ssh_public_key

  tags = { Name = "airflow-ec2-key", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Security Group
# ──────────────────────────────────────────────
resource "aws_security_group" "airflow" {
  name        = "airflow-ec2-sg"
  description = "Airflow EC2 security group"
  vpc_id      = var.vpc_id

  # SSH — your IP only
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "SSH access"
  }

  # Airflow UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
    description = "Airflow web UI"
  }

  # All outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "airflow-ec2-sg", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# IAM Role for EC2 — Airflow needs AWS access
# ──────────────────────────────────────────────
resource "aws_iam_role" "airflow_ec2" {
  name = "airflow-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "airflow-ec2-role", ManagedBy = "Terraform" }
}

resource "aws_iam_instance_profile" "airflow_ec2" {
  name = "airflow-ec2-profile"
  role = aws_iam_role.airflow_ec2.name
}

resource "aws_iam_role_policy" "airflow_ec2" {
  name = "airflow-ec2-policy"
  role = aws_iam_role.airflow_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerAccess"
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:StopTrainingJob",
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:DescribeEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DeleteEndpoint"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::mlops-dev-gold",
          "arn:aws:s3:::mlops-dev-gold/*",
          "arn:aws:s3:::mlops-dev-mlflow-store",
          "arn:aws:s3:::mlops-dev-mlflow-store/*"
        ]
      },
      {
        Sid    = "PassSageMakerRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sagemaker-execution-role"
      },
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/mlops/*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# EC2 Instance — t3.medium (2 vCPU, 4 GB)
# ──────────────────────────────────────────────
resource "aws_instance" "airflow" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.airflow.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.airflow.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow_ec2.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # ── Install Docker + git ────────────────────────────────
    dnf update -y
    dnf install -y docker git
    systemctl start docker
    systemctl enable docker
    usermod -aG docker ec2-user

    # ── Install Docker Compose ──────────────────────────────
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # ── Fix SSH: Amazon Linux 2023 uses EC2 Instance Connect ─
    # Disable it so standard authorized_keys works reliably
    cat > /etc/ssh/sshd_config.d/99-local.conf <<SSHCONF
    AuthorizedKeysCommand none
    AuthorizedKeysCommandUser none
    UsePAM no
    SSHCONF

    # Prepend UsePAM no before the Include so it wins
    sed -i "1s/^/UsePAM no\n/" /etc/ssh/sshd_config
    systemctl restart sshd

    # ── Fix logs permissions for Airflow (uid 50000 in container) ──
    mkdir -p /home/ec2-user/mlops/airflow/logs/scheduler
    mkdir -p /home/ec2-user/mlops/airflow/plugins
    chown -R 50000:0 /home/ec2-user/mlops/airflow/logs
    chown -R 50000:0 /home/ec2-user/mlops/airflow/plugins

    # ── Clone MLOps repo ────────────────────────────────────
    cd /home/ec2-user
    git clone https://github.com/Venkat8538/mlops-fraud-detection.git mlops
    chown -R ec2-user:ec2-user mlops

    # ── Fix logs ownership after clone (git may reset it) ───
    chown -R 50000:0 mlops/airflow/logs mlops/airflow/plugins

    # ── Start Airflow ────────────────────────────────────────
    cd /home/ec2-user/mlops
    docker-compose -f airflow/docker-compose.yml up -d

    echo "✅ Airflow bootstrap complete"
  EOF

  tags = { Name = "mlops-airflow", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Elastic IP — gives Airflow a stable public IP
# ──────────────────────────────────────────────
resource "aws_eip" "airflow" {
  instance   = aws_instance.airflow.id
  domain     = "vpc"
  tags       = { Name = "mlops-airflow-eip", ManagedBy = "Terraform" }
}
