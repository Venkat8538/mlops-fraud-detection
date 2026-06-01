# Databricks notebook source
# MAGIC %md
# MAGIC # 00 - Setup
# MAGIC Creates Bronze / Silver / Gold schemas in Unity Catalog.
# MAGIC Each layer has its own dedicated S3 bucket.

# COMMAND ----------

CATALOG        = "workspace"
BRONZE_BUCKET  = "s3://mlops-dev-bronze"
SILVER_BUCKET  = "s3://mlops-dev-silver"
GOLD_BUCKET    = "s3://mlops-dev-gold"

# COMMAND ----------

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.bronze MANAGED LOCATION '{BRONZE_BUCKET}'")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.silver MANAGED LOCATION '{SILVER_BUCKET}'")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.gold   MANAGED LOCATION '{GOLD_BUCKET}'")

print("✅ Schemas created:")
spark.sql(f"SHOW SCHEMAS IN {CATALOG}").show()
