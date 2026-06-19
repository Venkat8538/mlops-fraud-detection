"""
Fraud Detection — SageMaker Training Script
Reads Gold features from S3, trains XGBoost classifier, logs to MLflow.

Inputs  (via SageMaker channel):
    /opt/ml/input/data/train/  — training Parquet files from mlops-dev-gold

Outputs (written by SageMaker):
    /opt/ml/model/             — saved XGBoost model

S3 artifact structure (AAP-427):
    create_experiment/<tenant>/create_model_year_<YYYY>/run_id_<run_id>/namespace_run/model/
    create_factory/<model_name>/<tenant>_<model_name>_<date>/artifacts/metrics.json
"""

import os
import json
import argparse
import logging
import datetime
import boto3
import numpy as np
import pandas as pd
import xgboost as xgb
import mlflow
import mlflow.xgboost

from mlflow.models.signature import infer_signature
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    roc_auc_score, f1_score, precision_score,
    recall_score, confusion_matrix, classification_report
)

# ── Tenant config (AAP-427) ───────────────────
TENANT      = "fraud-detection"
NAMESPACE   = "fraud-detection"
MODEL_NAME  = "fraud-xgboost"
ENV         = "dev"
S3_BUCKET   = "mlops-dev-mlflow-store"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────
# Feature columns (must match Gold table schema)
# ──────────────────────────────────────────────
FEATURE_COLS = [
    "amount",
    "is_foreign",
    "is_night",
    "is_weekend",
    "is_high_value",
    "hour_of_day",
    "day_of_week",
    "merchant_category_enc",
    "amount_vs_avg_ratio",
    "amount_zscore",
    "txn_count_1h",
    "txn_count_24h",
    "txn_count_7d",
    "amount_sum_1h",
    "amount_sum_24h",
    "user_txn_count",
    "user_avg_amount",
    "user_std_amount",
    "user_unique_merchants",
    "user_foreign_txn_rate",
    "user_night_txn_rate",
    "user_prior_fraud_count",
    "merchant_txn_count",
    "merchant_avg_amount",
    "merchant_fraud_rate",
]

LABEL_COL = "is_fraud"


def parse_args():
    parser = argparse.ArgumentParser()

    # SageMaker passes hyperparameters as CLI args
    parser.add_argument("--max-depth",        type=int,   default=6)
    parser.add_argument("--n-estimators",     type=int,   default=200)
    parser.add_argument("--learning-rate",    type=float, default=0.1)
    parser.add_argument("--subsample",        type=float, default=0.8)
    parser.add_argument("--colsample-bytree", type=float, default=0.8)
    parser.add_argument("--scale-pos-weight", type=float, default=10.0)
    parser.add_argument("--test-size",        type=float, default=0.2)

    # MLflow tracking
    parser.add_argument("--mlflow-tracking-uri", type=str,
                        default=os.environ.get("MLFLOW_TRACKING_URI", "databricks"))
    parser.add_argument("--mlflow-experiment",   type=str,
                        default="/Users/ganjikunta.venkat@gmail.com/fraud-detection")

    # SageMaker paths
    parser.add_argument("--train",      type=str, default=os.environ.get("SM_CHANNEL_TRAIN", "/opt/ml/input/data/train"))
    parser.add_argument("--model-dir",  type=str, default=os.environ.get("SM_MODEL_DIR",     "/opt/ml/model"))
    parser.add_argument("--output-dir", type=str, default=os.environ.get("SM_OUTPUT_DIR",    "/opt/ml/output"))

    return parser.parse_args()


def load_data(train_dir):
    """Load all Parquet files from the SageMaker input channel."""
    logger.info(f"Loading data from {train_dir}")
    files = [
        os.path.join(train_dir, f)
        for f in os.listdir(train_dir)
        if f.endswith(".parquet")
    ]
    logger.info(f"Found {len(files)} Parquet files")
    df = pd.concat([pd.read_parquet(f) for f in files], ignore_index=True)
    logger.info(f"Loaded {len(df):,} rows, {len(df.columns)} columns")
    return df


def prepare_features(df):
    """Extract features and label, handle any nulls."""
    X = df[FEATURE_COLS].fillna(0)
    y = df[LABEL_COL]
    logger.info(f"Features: {X.shape}, Fraud rate: {y.mean():.3%}")
    return X, y


def train_model(X_train, y_train, params):
    """Train XGBoost with class imbalance handling."""
    model = xgb.XGBClassifier(
        max_depth        = params["max_depth"],
        n_estimators     = params["n_estimators"],
        learning_rate    = params["learning_rate"],
        subsample        = params["subsample"],
        colsample_bytree = params["colsample_bytree"],
        scale_pos_weight = params["scale_pos_weight"],  # handles class imbalance
        use_label_encoder = False,
        eval_metric      = "auc",
        random_state     = 42,
        n_jobs           = -1,
    )
    model.fit(
        X_train, y_train,
        eval_set=[(X_train, y_train)],
        verbose=50,
    )
    return model


def evaluate_model(model, X_test, y_test):
    """Compute all evaluation metrics."""
    y_pred      = model.predict(X_test)
    y_pred_prob = model.predict_proba(X_test)[:, 1]

    metrics = {
        "roc_auc":   round(roc_auc_score(y_test, y_pred_prob), 4),
        "f1":        round(f1_score(y_test, y_pred),            4),
        "precision": round(precision_score(y_test, y_pred),     4),
        "recall":    round(recall_score(y_test, y_pred),        4),
    }

    cm = confusion_matrix(y_test, y_pred)
    metrics["true_negatives"]  = int(cm[0][0])
    metrics["false_positives"] = int(cm[0][1])
    metrics["false_negatives"] = int(cm[1][0])
    metrics["true_positives"]  = int(cm[1][1])

    logger.info(f"Metrics: {metrics}")
    logger.info(f"\n{classification_report(y_test, y_pred, target_names=['legit', 'fraud'])}")

    return metrics


def get_feature_importance(model):
    """Return top 10 most important features."""
    importance = dict(zip(FEATURE_COLS, model.feature_importances_))
    return dict(sorted(importance.items(), key=lambda x: x[1], reverse=True)[:10])


def main():
    args = parse_args()

    params = {
        "max_depth":        args.max_depth,
        "n_estimators":     args.n_estimators,
        "learning_rate":    args.learning_rate,
        "subsample":        args.subsample,
        "colsample_bytree": args.colsample_bytree,
        "scale_pos_weight": args.scale_pos_weight,
    }

    run_date   = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    run_year   = datetime.datetime.utcnow().strftime("%Y")
    run_ts     = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")

    # ── Setup MLflow ──────────────────────────────
    mlflow.set_tracking_uri(args.mlflow_tracking_uri)
    mlflow.set_experiment(args.mlflow_experiment)

    with mlflow.start_run(run_name=f"{MODEL_NAME}-{run_date}") as run:
        run_id = run.info.run_id
        logger.info(f"MLflow run ID: {run_id}")

        # ── Tenant tags (AAP-427) ─────────────────
        mlflow.set_tags({
            "tenant":     TENANT,
            "namespace":  NAMESPACE,
            "model_name": MODEL_NAME,
            "env":        ENV,
            "run_date":   run_date,
        })

        # ── Load data ─────────────────────────────
        df = load_data(args.train)
        X, y = prepare_features(df)

        X_train, X_test, y_train, y_test = train_test_split(
            X, y,
            test_size    = args.test_size,
            random_state = 42,
            stratify     = y
        )
        logger.info(f"Train: {len(X_train):,}  Test: {len(X_test):,}")

        # ── Log parameters ────────────────────────
        mlflow.log_params(params)
        mlflow.log_param("test_size",        args.test_size)
        mlflow.log_param("train_rows",       len(X_train))
        mlflow.log_param("test_rows",        len(X_test))
        mlflow.log_param("fraud_rate_train", round(y_train.mean(), 4))
        mlflow.log_param("n_features",       len(FEATURE_COLS))
        mlflow.log_param("tenant",           TENANT)
        mlflow.log_param("namespace",        NAMESPACE)

        # ── Train ─────────────────────────────────
        logger.info("Training XGBoost model...")
        model = train_model(X_train, y_train, params)

        # ── Evaluate ──────────────────────────────
        metrics = evaluate_model(model, X_test, y_test)
        mlflow.log_metrics(metrics)

        # ── Feature importance ────────────────────
        top_features = get_feature_importance(model)
        logger.info(f"Top features: {top_features}")
        for feat, score in top_features.items():
            mlflow.log_metric(f"feat_{feat}", round(float(score), 4))

        # ── Log model with signature (AAP-427) ────
        signature     = infer_signature(X_train, model.predict(X_train))
        input_example = X_test.iloc[:5]

        mlflow.xgboost.log_model(
            model,
            artifact_path         = "model",
            registered_model_name = f"{TENANT}-{MODEL_NAME}",
            signature             = signature,
            input_example         = input_example,
        )

        # ── Save model for SageMaker ──────────────
        os.makedirs(args.model_dir, exist_ok=True)
        model_path = os.path.join(args.model_dir, "xgboost-model.json")
        model.save_model(model_path)
        logger.info(f"Model saved to {model_path}")

        # ── Write metrics locally for SageMaker output ──
        os.makedirs(args.output_dir, exist_ok=True)
        metrics_path = os.path.join(args.output_dir, "metrics.json")
        with open(metrics_path, "w") as f:
            json.dump(metrics, f, indent=2)

        # ── Upload to S3 — AAP-427 folder structure ──
        # Production Lab:
        #   create_experiment/<tenant>/create_model_year_<YYYY>/run_id_<run_id>/namespace_run/
        # Production Factory:
        #   create_factory/<model_name>/<tenant>_<model_name>_<date>/artifacts/
        s3 = boto3.client("s3")

        # Experiment path — metrics artifact
        experiment_key = (
            f"create_experiment/{TENANT}/create_model_year_{run_year}"
            f"/run_id_{run_id}/namespace_run/artifacts"
            f"/mft_aff_{run_id}_{run_date}/metrics.json"
        )
        s3.put_object(
            Bucket = S3_BUCKET,
            Key    = experiment_key,
            Body   = json.dumps(metrics, indent=2).encode(),
        )
        logger.info(f"Metrics uploaded → s3://{S3_BUCKET}/{experiment_key}")

        # Factory path — inference-ready metrics for Airflow quality gate
        factory_key = (
            f"create_factory/{MODEL_NAME}"
            f"/{TENANT}_{MODEL_NAME}_{run_ts}"
            f"/artifacts/metrics.json"
        )
        s3.put_object(
            Bucket = S3_BUCKET,
            Key    = factory_key,
            Body   = json.dumps(metrics, indent=2).encode(),
        )
        logger.info(f"Factory metrics → s3://{S3_BUCKET}/{factory_key}")

        # Store factory path in MLflow so Airflow can retrieve it
        mlflow.log_param("s3_factory_path", f"s3://{S3_BUCKET}/{factory_key}")
        mlflow.log_param("s3_experiment_path", f"s3://{S3_BUCKET}/{experiment_key}")

        logger.info(f"✅ Training complete — ROC AUC: {metrics['roc_auc']}")
        logger.info(f"   Precision: {metrics['precision']}  Recall: {metrics['recall']}  F1: {metrics['f1']}")


if __name__ == "__main__":
    main()
