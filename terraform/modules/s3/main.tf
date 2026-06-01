data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ──────────────────────────────────────────────
# Bronze — raw ingested data
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "bronze" {
  bucket        = "${var.name}-bronze"
  force_destroy = var.force_destroy
  tags = merge(var.tags, { Name = "${var.name}-bronze", Layer = "bronze" })
}

resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket                  = aws_s3_bucket.bronze.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# Silver — cleaned data
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "silver" {
  bucket        = "${var.name}-silver"
  force_destroy = var.force_destroy
  tags = merge(var.tags, { Name = "${var.name}-silver", Layer = "silver" })
}

resource "aws_s3_bucket_public_access_block" "silver" {
  bucket                  = aws_s3_bucket.silver.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# Gold — ML-ready features
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "gold" {
  bucket        = "${var.name}-gold"
  force_destroy = var.force_destroy
  tags = merge(var.tags, { Name = "${var.name}-gold", Layer = "gold" })
}

resource "aws_s3_bucket_public_access_block" "gold" {
  bucket                  = aws_s3_bucket.gold.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# MLflow — model artifacts
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "mlflow" {
  bucket        = "${var.name}-mlflow-store"
  force_destroy = var.force_destroy
  tags = merge(var.tags, { Name = "${var.name}-mlflow-store" })
}

resource "aws_s3_bucket_public_access_block" "mlflow" {
  bucket                  = aws_s3_bucket.mlflow.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# Spark — shuffle and temp data
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "spark" {
  bucket        = "${var.name}-spark"
  force_destroy = var.force_destroy
  tags = merge(var.tags, { Name = "${var.name}-spark" })
}

resource "aws_s3_bucket_public_access_block" "spark" {
  bucket                  = aws_s3_bucket.spark.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# Terraform state
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.name}-tf-state"
  force_destroy = false
  tags = merge(var.tags, { Name = "${var.name}-tf-state" })
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "${var.name}-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, { Name = "${var.name}-tfstate-lock" })
}
