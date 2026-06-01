output "bronze_bucket_name" {
  description = "Bronze layer S3 bucket name — raw ingested data"
  value       = aws_s3_bucket.bronze.bucket
}

output "bronze_bucket_arn" {
  value = aws_s3_bucket.bronze.arn
}

output "silver_bucket_name" {
  description = "Silver layer S3 bucket name — cleaned data"
  value       = aws_s3_bucket.silver.bucket
}

output "silver_bucket_arn" {
  value = aws_s3_bucket.silver.arn
}

output "gold_bucket_name" {
  description = "Gold layer S3 bucket name — ML-ready features"
  value       = aws_s3_bucket.gold.bucket
}

output "gold_bucket_arn" {
  value = aws_s3_bucket.gold.arn
}

output "mlflow_bucket_name" {
  description = "MLflow artifacts bucket name"
  value       = aws_s3_bucket.mlflow.bucket
}

output "mlflow_bucket_arn" {
  value = aws_s3_bucket.mlflow.arn
}

output "spark_bucket_name" {
  description = "Spark temp/shuffle bucket name"
  value       = aws_s3_bucket.spark.bucket
}

output "tfstate_bucket_name" {
  description = "Terraform remote state bucket name"
  value       = aws_s3_bucket.tfstate.bucket
}

output "tfstate_lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  value       = aws_dynamodb_table.tfstate_lock.name
}
