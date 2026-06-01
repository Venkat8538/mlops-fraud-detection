# Databricks notebook source
# MAGIC %md
# MAGIC # 03 - Gold Layer: Feature Engineering for Fraud Detection
# MAGIC Reads Silver clean transactions and engineers ML features:
# MAGIC
# MAGIC **Transaction features:**
# MAGIC - amount_vs_user_avg_ratio
# MAGIC - amount_zscore
# MAGIC
# MAGIC **Velocity features (window-based):**
# MAGIC - txn_count_1h, txn_count_24h, txn_count_7d
# MAGIC - amount_sum_1h, amount_sum_24h
# MAGIC
# MAGIC **User behaviour features:**
# MAGIC - user_avg_amount, user_std_amount
# MAGIC - user_unique_merchants
# MAGIC - user_fraud_rate (historical)
# MAGIC
# MAGIC **Risk features:**
# MAGIC - is_foreign, is_night, is_high_value, is_weekend
# MAGIC - merchant_category encoded

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql import Window

CATALOG      = "workspace"
SILVER_TABLE = f"{CATALOG}.silver.transactions_clean"
GOLD_TABLE   = f"{CATALOG}.gold.fraud_features"

# COMMAND ----------
# MAGIC %md ## Read Silver

# COMMAND ----------

df = spark.table(SILVER_TABLE)
print(f"Silver records: {df.count():,}")

# COMMAND ----------
# MAGIC %md ## User-Level Aggregate Features

# COMMAND ----------

user_stats = (df.groupBy("user_id")
    .agg(
        F.count("transaction_id")                    .alias("user_txn_count"),
        F.avg("amount")                              .alias("user_avg_amount"),
        F.stddev("amount")                           .alias("user_std_amount"),
        F.max("amount")                              .alias("user_max_amount"),
        F.countDistinct("merchant_id")               .alias("user_unique_merchants"),
        F.avg("is_foreign")                          .alias("user_foreign_txn_rate"),
        F.avg("is_night")                            .alias("user_night_txn_rate"),
        F.sum("is_fraud")                            .alias("user_prior_fraud_count"),
    )
)

# COMMAND ----------
# MAGIC %md ## Merchant-Level Risk Features

# COMMAND ----------

merchant_stats = (df.groupBy("merchant_id")
    .agg(
        F.count("transaction_id")                    .alias("merchant_txn_count"),
        F.avg("amount")                              .alias("merchant_avg_amount"),
        F.avg("is_fraud")                            .alias("merchant_fraud_rate"),
    )
)

# COMMAND ----------
# MAGIC %md ## Velocity Features (Window-based)
# MAGIC Count transactions per user in the last 1h, 24h, 7d

# COMMAND ----------

# Convert timestamp to Unix for window calculations
df_ts = df.withColumn("ts_unix", F.unix_timestamp("timestamp"))

# Window specs ordered by time per user
w_1h  = Window.partitionBy("user_id").orderBy("ts_unix").rangeBetween(-3600,        0)
w_24h = Window.partitionBy("user_id").orderBy("ts_unix").rangeBetween(-86400,       0)
w_7d  = Window.partitionBy("user_id").orderBy("ts_unix").rangeBetween(-86400 * 7,   0)

df_velocity = (df_ts
    .withColumn("txn_count_1h",   F.count("transaction_id").over(w_1h))
    .withColumn("txn_count_24h",  F.count("transaction_id").over(w_24h))
    .withColumn("txn_count_7d",   F.count("transaction_id").over(w_7d))
    .withColumn("amount_sum_1h",  F.sum("amount").over(w_1h))
    .withColumn("amount_sum_24h", F.sum("amount").over(w_24h))
)

# COMMAND ----------
# MAGIC %md ## Join All Features Together

# COMMAND ----------

df_gold = (df_velocity
    .join(user_stats,     on="user_id",     how="left")
    .join(merchant_stats, on="merchant_id", how="left")

    # Amount vs user average ratio (how unusual is this transaction?)
    .withColumn("amount_vs_avg_ratio",
        F.when(F.col("user_avg_amount") > 0,
               F.col("amount") / F.col("user_avg_amount"))
         .otherwise(1.0))

    # Z-score of amount for this user
    .withColumn("amount_zscore",
        F.when(F.col("user_std_amount") > 0,
               (F.col("amount") - F.col("user_avg_amount")) / F.col("user_std_amount"))
         .otherwise(0.0))

    # Fill nulls for new users with no history
    .fillna({
        "user_std_amount":       0.0,
        "user_prior_fraud_count": 0,
        "merchant_fraud_rate":   0.0,
        "user_foreign_txn_rate": 0.0,
        "user_night_txn_rate":   0.0,
    })

    # Encode merchant category as integer index
    .withColumn("merchant_category_enc",
        F.when(F.col("merchant_category") == "luxury_goods",   9)
         .when(F.col("merchant_category") == "electronics",    8)
         .when(F.col("merchant_category") == "atm_withdrawal", 7)
         .when(F.col("merchant_category") == "travel",         6)
         .when(F.col("merchant_category") == "entertainment",  5)
         .when(F.col("merchant_category") == "online_retail",  4)
         .when(F.col("merchant_category") == "restaurant",     3)
         .when(F.col("merchant_category") == "pharmacy",       2)
         .when(F.col("merchant_category") == "gas_station",    1)
         .otherwise(0))

    # Select final feature set
    .select(
        # IDs
        "transaction_id",
        "user_id",
        "merchant_id",
        "timestamp",

        # Raw features
        "amount",
        "is_foreign",
        "is_night",
        "is_weekend",
        "is_high_value",
        "hour_of_day",
        "day_of_week",
        "merchant_category_enc",

        # Engineered transaction features
        "amount_vs_avg_ratio",
        "amount_zscore",

        # Velocity features
        "txn_count_1h",
        "txn_count_24h",
        "txn_count_7d",
        "amount_sum_1h",
        "amount_sum_24h",

        # User history features
        "user_txn_count",
        "user_avg_amount",
        "user_std_amount",
        "user_unique_merchants",
        "user_foreign_txn_rate",
        "user_night_txn_rate",
        "user_prior_fraud_count",

        # Merchant risk features
        "merchant_txn_count",
        "merchant_avg_amount",
        "merchant_fraud_rate",

        # Label
        "is_fraud",
    )
    .withColumn("gold_ts", F.current_timestamp())
)

print(f"Gold feature records: {df_gold.count():,}")
df_gold.printSchema()

# COMMAND ----------
# MAGIC %md ## Write to Gold Delta Table

# COMMAND ----------

(df_gold.write
    .format("delta")
    .mode("overwrite")
    .option("overwriteSchema", "true")
    .saveAsTable(GOLD_TABLE)
)

print(f"✅ Written to {GOLD_TABLE}")

# COMMAND ----------
# MAGIC %md ## Feature Summary Statistics

# COMMAND ----------

print("=== Feature Stats by Fraud Label ===")
spark.sql(f"""
    SELECT
        is_fraud,
        COUNT(*)                                AS count,
        ROUND(AVG(amount), 2)                   AS avg_amount,
        ROUND(AVG(amount_vs_avg_ratio), 2)      AS avg_amount_ratio,
        ROUND(AVG(txn_count_1h), 2)             AS avg_txn_1h,
        ROUND(AVG(txn_count_24h), 2)            AS avg_txn_24h,
        ROUND(AVG(is_foreign), 2)               AS foreign_rate,
        ROUND(AVG(is_night), 2)                 AS night_rate,
        ROUND(AVG(merchant_fraud_rate), 4)      AS merchant_fraud_rate
    FROM {GOLD_TABLE}
    GROUP BY is_fraud
    ORDER BY is_fraud
""").show()
