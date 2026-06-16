"""
Launch SageMaker Training Job for Fraud Detection.

Run this from:
  - Your local machine:    python launch_training.py
  - SageMaker Studio:      open terminal → python launch_training.py

Prerequisites:
  - AWS credentials configured (aws configure)
  - Training data exported from Databricks (04_export_gold_to_s3.py ran)
  - train.py uploaded to S3 (see upload command below)

Upload training script to S3 first:
  aws s3 cp sagemaker/training/train.py \
    s3://mlops-dev-mlflow-store/sagemaker/code/train.py
"""

import os
import boto3
import sagemaker
from sagemaker.xgboost import XGBoost

# ── Config ──────────────────────────────────────────────
AWS_REGION         = "us-east-1"
ROLE_ARN           = "arn:aws:iam::482227257362:role/sagemaker-execution-role"
TRAINING_DATA_PATH = "s3://mlops-dev-mlflow-store/sagemaker/training-data"
OUTPUT_PATH        = "s3://mlops-dev-mlflow-store/sagemaker/model-output"
CODE_PATH          = "s3://mlops-dev-mlflow-store/sagemaker/code"

# Databricks MLflow — paste your workspace URL and token
DATABRICKS_HOST    = "https://dbc-c586aafa-13e2.cloud.databricks.com"
DATABRICKS_TOKEN   = os.environ.get("DATABRICKS_TOKEN", "")
MLFLOW_EXPERIMENT  = "/Users/ganjikunta.venkat@gmail.com/fraud-detection"

# ── Session ─────────────────────────────────────────────
boto_session      = boto3.Session(region_name=AWS_REGION)
sagemaker_session = sagemaker.Session(boto_session=boto_session)

# ── Estimator ───────────────────────────────────────────
estimator = XGBoost(
    entry_point       = "train.py",
    source_dir        = CODE_PATH,
    role              = ROLE_ARN,
    instance_count    = 1,
    instance_type     = "ml.m5.xlarge",   # ~$0.23/hour
    framework_version = "1.7-1",
    py_version        = "py3",
    output_path       = OUTPUT_PATH,
    sagemaker_session = sagemaker_session,

    hyperparameters = {
        "max-depth":        6,
        "n-estimators":     200,
        "learning-rate":    0.1,
        "subsample":        0.8,
        "colsample-bytree": 0.8,
        "scale-pos-weight": 10,   # handles 2% fraud class imbalance
        "test-size":        0.2,
        "mlflow-experiment": MLFLOW_EXPERIMENT,
    },

    environment = {
        "DATABRICKS_HOST":     DATABRICKS_HOST,
        "DATABRICKS_TOKEN":    DATABRICKS_TOKEN,
        "MLFLOW_TRACKING_URI": "databricks",
    }
)

# ── Launch ──────────────────────────────────────────────
print("Launching SageMaker training job...")
estimator.fit(
    inputs   = {"train": TRAINING_DATA_PATH},
    job_name = "fraud-detection-xgboost",
    wait     = True,   # blocks until job completes (~5-10 mins)
    logs     = True,   # stream logs to terminal
)

print("✅ Training complete!")
print(f"Model artifacts: {OUTPUT_PATH}/fraud-detection-xgboost/output/model.tar.gz")
