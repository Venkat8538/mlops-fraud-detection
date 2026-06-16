# Databricks notebook source
# MAGIC %md
# MAGIC # 02 - Silver Layer: Cleaning & Standardization
# MAGIC Reads Bronze raw transactions and applies:
# MAGIC - Null checks and deduplication
# MAGIC - Data type enforcement
# MAGIC - Amount outlier removal (keep < $10,000)
# MAGIC - Derived columns: hour_of_day, day_of_week, is_night

# COMMAND ----------

from pyspark.sql import functions as F

CATALOG       = "workspace"
BRONZE_TABLE  = f"{CATALOG}.bronze.transactions_raw"
SILVER_TABLE  = f"{CATALOG}.silver.transactions_clean"

# COMMAND ----------
# MAGIC %md ## Read Bronze

# COMMAND ----------

df_bronze = spark.table(BRONZE_TABLE)
print(f"Bronze records: {df_bronze.count():,}")

# COMMAND ----------
# MAGIC %md ## Clean & Standardize

# COMMAND ----------

df_silver = (df_bronze
    # Drop duplicates on transaction_id
    .dropDuplicates(["transaction_id"])

    # Drop nulls on critical columns
    .dropna(subset=["transaction_id", "user_id", "amount", "timestamp"])

    # Remove invalid amounts
    .filter(F.col("amount") > 0)
    .filter(F.col("amount") < 10_000)

    # Standardize currency to uppercase
    .withColumn("currency", F.upper(F.col("currency")))

    # Derive time features
    .withColumn("hour_of_day",   F.hour("timestamp"))
    .withColumn("day_of_week",   F.dayofweek("timestamp"))    # 1=Sun, 7=Sat
    .withColumn("is_weekend",    (F.dayofweek("timestamp").isin([1, 7])).cast("int"))
    .withColumn("is_night",      ((F.hour("timestamp").between(0, 5)) | (F.hour("timestamp") == 23)).cast("int"))

    # Flag high-value transactions
    .withColumn("is_high_value", (F.col("amount") > 500).cast("int"))

    # Add silver metadata
    .withColumn("silver_ts",     F.current_timestamp())

    # Drop raw ingestion metadata
    .drop("ingestion_source")
)

print(f"Silver records after cleaning: {df_silver.count():,}")

# COMMAND ----------
# MAGIC %md ## Validate — No Nulls in Critical Columns

# COMMAND ----------

critical_cols = ["transaction_id", "user_id", "amount", "timestamp", "is_fraud"]
for col in critical_cols:
    null_count = df_silver.filter(F.col(col).isNull()).count()
    status = "✅" if null_count == 0 else "❌"
    print(f"{status} {col}: {null_count} nulls")

# COMMAND ----------
# MAGIC %md ## Write to Silver Delta Table

# COMMAND ----------

(df_silver.write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(SILVER_TABLE)
)

print(f"✅ Written to {SILVER_TABLE}")

spark.sql(f"""
    SELECT
        is_fraud,
        is_night,
        is_weekend,
        COUNT(*)            AS count,
        ROUND(AVG(amount), 2) AS avg_amount
    FROM {SILVER_TABLE}
    GROUP BY is_fraud, is_night, is_weekend
    ORDER BY is_fraud, is_night
""").show()
