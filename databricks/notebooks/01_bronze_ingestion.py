# Databricks notebook source
# MAGIC %md
# MAGIC # 01 - Bronze Layer: Raw Transaction Ingestion
# MAGIC Generates synthetic fraud transaction data and writes it
# MAGIC as-is to the Bronze Delta table — no transformations.
# MAGIC
# MAGIC Schema:
# MAGIC   transaction_id, user_id, merchant_id, amount, currency,
# MAGIC   timestamp, merchant_category, location_country,
# MAGIC   is_foreign, device_type, ip_address, is_fraud (label)

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.types import *
import random

CATALOG = "workspace"
SCHEMA  = "bronze"
TABLE   = f"{CATALOG}.{SCHEMA}.transactions_raw"

# COMMAND ----------
# MAGIC %md ## Generate Synthetic Fraud Transaction Data

# COMMAND ----------

# Reproducible seed
random.seed(42)

NUM_USERS       = 1_000
NUM_MERCHANTS   = 500
NUM_TRANSACTIONS = 100_000
FRAUD_RATE      = 0.02   # 2% fraud — realistic for card fraud

merchant_categories = [
    "grocery", "restaurant", "gas_station", "online_retail",
    "electronics", "travel", "pharmacy", "entertainment",
    "atm_withdrawal", "luxury_goods"
]

device_types = ["mobile", "desktop", "tablet", "pos_terminal"]
countries    = ["US", "US", "US", "US", "US", "MX", "CA", "GB", "CN", "NG"]

data = []
for i in range(NUM_TRANSACTIONS):
    user_id     = f"user_{random.randint(1, NUM_USERS):05d}"
    merchant_id = f"merchant_{random.randint(1, NUM_MERCHANTS):05d}"
    category    = random.choice(merchant_categories)
    country     = random.choice(countries)
    is_foreign  = 1 if country != "US" else 0
    device      = random.choice(device_types)

    # Fraud logic — fraudulent txns tend to be:
    # higher amount, foreign, late night, luxury/electronics
    is_fraud = 0
    amount = round(random.lognormvariate(4.0, 1.2), 2)  # normal txn

    if random.random() < FRAUD_RATE:
        is_fraud = 1
        amount   = round(random.uniform(500, 5000), 2)  # large amounts
        country  = random.choice(["CN", "NG", "RU", "MX"])
        is_foreign = 1
        category = random.choice(["luxury_goods", "electronics", "atm_withdrawal"])

    # Timestamp: last 90 days, biased to daytime for legit, nighttime for fraud
    if is_fraud:
        hour = random.choice([0, 1, 2, 3, 23])
    else:
        hour = random.randint(6, 22)

    day_offset = random.randint(0, 89)
    ts = f"2026-{3 if day_offset < 31 else (4 if day_offset < 61 else 5):02d}-{(day_offset % 30) + 1:02d} {hour:02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}"

    data.append((
        f"txn_{i:08d}",
        user_id,
        merchant_id,
        float(amount),
        "USD",
        ts,
        category,
        country,
        is_foreign,
        device,
        f"192.168.{random.randint(0,255)}.{random.randint(0,255)}",
        is_fraud
    ))

# COMMAND ----------
# MAGIC %md ## Create Spark DataFrame and Write to Bronze Delta Table

# COMMAND ----------

schema = StructType([
    StructField("transaction_id",      StringType(),  False),
    StructField("user_id",             StringType(),  False),
    StructField("merchant_id",         StringType(),  False),
    StructField("amount",              DoubleType(),  False),
    StructField("currency",            StringType(),  False),
    StructField("timestamp",           StringType(),  False),
    StructField("merchant_category",   StringType(),  False),
    StructField("location_country",    StringType(),  False),
    StructField("is_foreign",          IntegerType(), False),
    StructField("device_type",         StringType(),  False),
    StructField("ip_address",          StringType(),  False),
    StructField("is_fraud",            IntegerType(), False),
])

df_raw = spark.createDataFrame(data, schema=schema) \
              .withColumn("timestamp",        F.to_timestamp("timestamp")) \
              .withColumn("ingestion_ts",     F.current_timestamp()) \
              .withColumn("ingestion_source", F.lit("synthetic_generator_v1"))

print(f"Total records : {df_raw.count():,}")
print(f"Fraud records : {df_raw.filter('is_fraud=1').count():,}")
df_raw.printSchema()

# COMMAND ----------
# MAGIC %md ## Write to Bronze Delta Table (append mode — idempotent)

# COMMAND ----------

(df_raw.write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(TABLE)
)

print(f"✅ Written to {TABLE}")
spark.sql(f"SELECT is_fraud, COUNT(*) as count FROM {TABLE} GROUP BY is_fraud").show()

# COMMAND ----------
# MAGIC %md ## Quick Data Quality Check

# COMMAND ----------

print("=== Bronze Table Stats ===")
spark.sql(f"""
    SELECT
        COUNT(*)                                    AS total_transactions,
        SUM(is_fraud)                               AS fraud_count,
        ROUND(SUM(is_fraud) / COUNT(*) * 100, 2)   AS fraud_pct,
        ROUND(AVG(amount), 2)                       AS avg_amount,
        MIN(timestamp)                              AS earliest_txn,
        MAX(timestamp)                              AS latest_txn
    FROM {TABLE}
""").show()
