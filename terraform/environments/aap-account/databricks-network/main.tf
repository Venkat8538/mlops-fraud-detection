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
resource "aws_vpc" "databricks" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "databricks-dev-vpc", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Internet Gateway
# ──────────────────────────────────────────────
resource "aws_internet_gateway" "databricks" {
  vpc_id = aws_vpc.databricks.id
  tags   = { Name = "databricks-dev-igw", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Single NAT Gateway (dev — one AZ only)
# ──────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.databricks]
  tags       = { Name = "databricks-dev-nat-eip", ManagedBy = "Terraform" }
}

resource "aws_nat_gateway" "databricks" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.databricks]
  tags          = { Name = "databricks-dev-nat", ManagedBy = "Terraform" }
}

# ──────────────────────────────────────────────
# Public subnets (2) — NAT gateway lives here
# ──────────────────────────────────────────────
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.databricks.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "databricks-dev-public-${count.index + 1}", ManagedBy = "Terraform" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.databricks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.databricks.id
  }

  tags = { Name = "databricks-dev-public-rt", ManagedBy = "Terraform" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────
# Private subnets (2) — Databricks cluster nodes run here
# ──────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.databricks.id
  cidr_block        = cidrsubnet("10.0.0.0/16", 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "databricks-dev-private-${count.index + 1}", ManagedBy = "Terraform" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.databricks.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.databricks.id
  }

  tags = { Name = "databricks-dev-private-rt", ManagedBy = "Terraform" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ──────────────────────────────────────────────
# Security group — Databricks cluster nodes
# ──────────────────────────────────────────────
resource "aws_security_group" "databricks" {
  name        = "databricks-dev-sg"
  description = "Databricks cluster node communication"
  vpc_id      = aws_vpc.databricks.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Node-to-node"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "databricks-dev-sg", ManagedBy = "Terraform" }
}
