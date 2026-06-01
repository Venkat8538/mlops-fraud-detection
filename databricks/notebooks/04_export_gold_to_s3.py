# Databricks notebook source
# MAGIC %md
# MAGIC # 04 - Export Gold Features to S3 for SageMaker
# MAGIC Exports the Gold Delta table as Parquet files to S3
# MAGIC so SageMaker can read it as a training input channel.

# COMMAND ----------

GOLD_TABLE     = "workspace.gold.fraud_features"
EXPORT_S3_PATH = "s3://mlops-dev-mlflow-store/sagemaker/training-data"

# COMMAND ----------

df_gold = spark.table(GOLD_TABLE)
print(f"Gold records  : {df_gold.count():,}")
print(f"Fraud records : {df_gold.filter('is_fraud=1').count():,}")
print(f"Features      : {len(df_gold.columns)}")

# COMMAND ----------

(df_gold
    .coalesce(4)
    .write
    .mode("overwrite")
    .parquet(EXPORT_S3_PATH)
)

print(f"✅ Exported to {EXPORT_S3_PATH}")
print(f"   Next step: run launch_training.py from your local machine or SageMaker Studio")
