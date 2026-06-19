"""
Launch SageMaker Training Job for Fraud Detection.

Run this from:
  - Your local machine:    python launch_training.py
  - SageMaker Studio:      open terminal → python launch_training.py

Prerequisites:
  - AWS credentials configured (aws configure)
  - Training data exported from Databricks (04_export_gold_to_s3.py ran)
  - train.py uploaded to S3:
      aws s3 cp sagemaker/training/train.py \
        s3://mlops-dev-mlflow-store/sagemaker/code/train.py

S3 artifact structure (AAP-427):
  create_experiment/fraud-detection/create_model_year_<YYYY>/run_id_<run_id>/namespace_run/
  create_factory/fraud-xgboost/fraud-detection_fraud-xgboost_<ts>/artifacts/metrics.json
"""

import os
import datetime
import boto3
import sagemaker
from sagemaker.xgboost import XGBoost

# ── Tenant config (AAP-427) ──────────────────────────────
TENANT     = "fraud-detection"
MODEL_NAME = "fraud-xgboost"

# ── AWS / S3 config ──────────────────────────────────────
AWS_REGION         = "us-east-1"
ROLE_ARN           = "arn:aws:iam::482227257362:role/sagemaker-execution-role"
S3_BUCKET          = "mlops-dev-mlflow-store"
TRAINING_DATA_PATH = f"s3://{S3_BUCKET}/sagemaker/training-data"
OUTPUT_PATH        = f"s3://{S3_BUCKET}/create_factory/{MODEL_NAME}"
CODE_PATH          = f"s3://{S3_BUCKET}/sagemaker/code"

# ── Databricks MLflow ────────────────────────────────────
DATABRICKS_HOST   = "https://dbc-c586aafa-13e2.cloud.databricks.com"
DATABRICKS_TOKEN  = os.environ.get("DATABRICKS_TOKEN", "")
MLFLOW_EXPERIMENT = "/Users/ganjikunta.venkat@gmail.com/fraud-detection"

# ── Job name (unique per run) ────────────────────────────
run_ts   = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
JOB_NAME = f"{TENANT}-{MODEL_NAME}-{run_ts}"

# ── Session ──────────────────────────────────────────────
boto_session      = boto3.Session(region_name=AWS_REGION)
sagemaker_session = sagemaker.Session(boto_session=boto_session)

# ── Estimator ────────────────────────────────────────────
estimator = XGBoost(
    entry_point       = "train.py",
    source_dir        = CODE_PATH,
    role              = ROLE_ARN,
    instance_count    = 1,
    instance_type     = "ml.m5.xlarge",
    framework_version = "1.7-1",
    py_version        = "py3",
    output_path       = OUTPUT_PATH,
    sagemaker_session = sagemaker_session,

    hyperparameters = {
        "max-depth":         6,
        "n-estimators":      200,
        "learning-rate":     0.1,
        "subsample":         0.8,
        "colsample-bytree":  0.8,
        "scale-pos-weight":  10,
        "test-size":         0.2,
        "mlflow-experiment": MLFLOW_EXPERIMENT,
    },

    environment = {
        "DATABRICKS_HOST":     DATABRICKS_HOST,
        "DATABRICKS_TOKEN":    DATABRICKS_TOKEN,
        "MLFLOW_TRACKING_URI": "databricks",
    }
)

# ── Launch ───────────────────────────────────────────────
print(f"Launching SageMaker training job: {JOB_NAME}")
print(f"Tenant:    {TENANT}")
print(f"Output:    {OUTPUT_PATH}/{JOB_NAME}/")
estimator.fit(
    inputs   = {"train": TRAINING_DATA_PATH},
    job_name = JOB_NAME,
    wait     = True,
    logs     = True,
)

print("✅ Training complete!")
print(f"Experiment artifacts: s3://{S3_BUCKET}/create_experiment/{TENANT}/")
print(f"Factory artifacts:    s3://{S3_BUCKET}/create_factory/{MODEL_NAME}/")
