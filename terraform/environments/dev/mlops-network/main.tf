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

data "aws_availability_zones" "available" {
  state = "available"
}

# ──────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────
resource "aws_vpc" "mlops" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "mlops-dev-vpc", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Internet Gateway — public internet access
# ──────────────────────────────────────────────
resource "aws_internet_gateway" "mlops" {
  vpc_id = aws_vpc.mlops.id
  tags   = { Name = "mlops-dev-igw", ManagedBy = "Terraform" }
}

# NAT Gateway removed — Airflow EC2 runs in public subnet
# Add back when moving to production with private subnets

# ──────────────────────────────────────────────
# Public subnets (2) — Airflow EC2, load balancers
# ──────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.mlops.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "mlops-dev-public-${count.index + 1}", ManagedBy = "Terraform" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.mlops.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mlops.id
  }

  tags = { Name = "mlops-dev-public-rt", ManagedBy = "Terraform" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────
# Private subnets (2) — Databricks cluster nodes
# No internet route — isolated for cluster traffic
# ──────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.mlops.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "mlops-dev-private-${count.index + 1}", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Security group — Databricks cluster nodes
# ──────────────────────────────────────────────
resource "aws_security_group" "mlops" {
  name        = "mlops-dev-sg"
  description = "MLOps cluster node communication"
  vpc_id      = aws_vpc.mlops.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Node-to-node"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "mlops-dev-sg", ManagedBy = "Terraform" }
}
