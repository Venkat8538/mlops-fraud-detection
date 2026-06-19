"""
Fraud Detection MLOps Pipeline DAG

Schedule: Daily at 2am
Pipeline:
  1. Trigger Databricks Bronze ingestion
  2. Trigger Databricks Silver cleaning
  3. Trigger Databricks Gold feature engineering
  4. Export Gold features to S3
  5. Launch SageMaker training job
  6. Evaluate model metrics (AUC > 0.90 threshold)
  7. Deploy to SageMaker endpoint if metrics pass
"""

from datetime import datetime, timedelta
import boto3
import json
import time
import requests

from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.empty import EmptyOperator
from airflow.models import Variable

# ── Config ────────────────────────────────────────────────────
DATABRICKS_HOST      = "https://dbc-c586aafa-13e2.cloud.databricks.com"
DATABRICKS_TOKEN     = Variable.get("DATABRICKS_TOKEN", default_var=None)
AWS_REGION           = "us-east-1"
SAGEMAKER_ROLE_ARN   = "arn:aws:iam::482227257362:role/sagemaker-execution-role"
TRAINING_DATA_PATH   = "s3://mlops-dev-mlflow-store/sagemaker/training-data"
AUC_THRESHOLD        = 0.90

# ── Tenant config (AAP-427) ───────────────────────────────────
TENANT      = "fraud-detection"
MODEL_NAME  = "fraud-xgboost"
S3_BUCKET   = "mlops-dev-mlflow-store"
OUTPUT_PATH = f"s3://{S3_BUCKET}/create_factory/{MODEL_NAME}"

# Repo-based paths — not tied to a personal user workspace
# Source of truth is GitHub: Venkat8538/mlops-fraud-detection
NOTEBOOK_REPO_BASE = "/Repos/ganjikunta.venkat@gmail.com/mlops-fraud-detection/databricks/notebooks"

NOTEBOOK_PATHS = {
    "bronze": f"{NOTEBOOK_REPO_BASE}/01_bronze_ingestion",
    "silver": f"{NOTEBOOK_REPO_BASE}/02_silver_cleaning",
    "gold":   f"{NOTEBOOK_REPO_BASE}/03_gold_features",
    "export": f"{NOTEBOOK_REPO_BASE}/04_export_gold_to_s3",
}

# ── Default args ──────────────────────────────────────────────
default_args = {
    "owner":            "mlops",
    "retries":          1,
    "retry_delay":      timedelta(minutes=5),
    "email_on_failure": False,
}


# ── Helper: run Databricks notebook ──────────────────────────
def run_databricks_notebook(notebook_path, **context):
    headers = {
        "Authorization": f"Bearer {DATABRICKS_TOKEN}",
        "Content-Type":  "application/json"
    }

    # Submit run
    run_payload = {
        "run_name": f"airflow-{notebook_path.split('/')[-1]}",
        "existing_cluster_id": Variable.get("DATABRICKS_CLUSTER_ID"),
        "notebook_task": {"notebook_path": notebook_path}
    }
    response = requests.post(
        f"{DATABRICKS_HOST}/api/2.1/jobs/runs/submit",
        headers=headers,
        json=run_payload
    )
    run_id = response.json()["run_id"]
    print(f"Submitted run {run_id} for {notebook_path}")

    # Poll until complete
    while True:
        status = requests.get(
            f"{DATABRICKS_HOST}/api/2.1/jobs/runs/get?run_id={run_id}",
            headers=headers
        ).json()

        life_cycle = status["state"]["life_cycle_state"]
        print(f"Run {run_id} status: {life_cycle}")

        if life_cycle == "TERMINATED":
            result = status["state"]["result_state"]
            if result != "SUCCESS":
                raise Exception(f"Notebook failed: {result}")
            print(f"✅ Notebook {notebook_path} completed")
            return run_id

        if life_cycle in ["SKIPPED", "INTERNAL_ERROR"]:
            raise Exception(f"Notebook error: {life_cycle}")

        time.sleep(30)


# ── Task functions ────────────────────────────────────────────
def run_bronze(**context):
    run_databricks_notebook(NOTEBOOK_PATHS["bronze"], **context)

def run_silver(**context):
    run_databricks_notebook(NOTEBOOK_PATHS["silver"], **context)

def run_gold(**context):
    run_databricks_notebook(NOTEBOOK_PATHS["gold"], **context)

def run_export(**context):
    run_databricks_notebook(NOTEBOOK_PATHS["export"], **context)

def launch_sagemaker_training(**context):
    import datetime
    import sagemaker
    from sagemaker.xgboost import XGBoost

    run_ts   = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    job_name = f"{TENANT}-{MODEL_NAME}-{run_ts}"

    boto_session      = boto3.Session(region_name=AWS_REGION)
    sagemaker_session = sagemaker.Session(boto_session=boto_session)

    estimator = XGBoost(
        entry_point       = "train.py",
        source_dir        = f"s3://{S3_BUCKET}/sagemaker/code",
        role              = SAGEMAKER_ROLE_ARN,
        instance_count    = 1,
        instance_type     = "ml.m5.xlarge",
        framework_version = "1.7-1",
        py_version        = "py3",
        output_path       = OUTPUT_PATH,
        sagemaker_session = sagemaker_session,
        hyperparameters   = {
            "max-depth":         6,
            "n-estimators":      200,
            "learning-rate":     0.1,
            "scale-pos-weight":  10,
            "test-size":         0.2,
            "mlflow-experiment": "/Users/ganjikunta.venkat@gmail.com/fraud-detection",
        },
        environment = {
            "DATABRICKS_HOST":     DATABRICKS_HOST,
            "DATABRICKS_TOKEN":    DATABRICKS_TOKEN,
            "MLFLOW_TRACKING_URI": "databricks",
        }
    )

    estimator.fit(
        inputs   = {"train": TRAINING_DATA_PATH},
        job_name = job_name,
        wait     = True,
        logs     = True,
    )

    context["ti"].xcom_push(key="sagemaker_job_name", value=job_name)
    context["ti"].xcom_push(key="run_ts", value=run_ts)
    print(f"✅ Training complete: {job_name}")


def evaluate_model(**context):
    job_name  = context["ti"].xcom_pull(key="sagemaker_job_name")
    run_ts    = context["ti"].xcom_pull(key="run_ts")
    sm_client = boto3.client("sagemaker", region_name=AWS_REGION)
    s3_client = boto3.client("s3", region_name=AWS_REGION)

    job      = sm_client.describe_training_job(TrainingJobName=job_name)
    model_s3 = job["ModelArtifacts"]["S3ModelArtifacts"]
    print(f"Model artifacts: {model_s3}")

    # Read metrics from AAP-427 factory path
    # train.py writes: create_factory/<model>/<tenant>_<model>_<ts>/artifacts/metrics.json
    metrics_key = (
        f"create_factory/{MODEL_NAME}"
        f"/{TENANT}_{MODEL_NAME}_{run_ts}"
        f"/artifacts/metrics.json"
    )
    try:
        obj     = s3_client.get_object(Bucket=S3_BUCKET, Key=metrics_key)
        metrics = json.loads(obj["Body"].read())
        auc     = metrics.get("roc_auc", 0)
        print(f"Metrics path: s3://{S3_BUCKET}/{metrics_key}")
        print(f"Model AUC: {auc}  Threshold: {AUC_THRESHOLD}")
        context["ti"].xcom_push(key="model_auc", value=auc)
        context["ti"].xcom_push(key="model_s3",  value=model_s3)
        return auc
    except Exception as e:
        print(f"Could not read metrics from {metrics_key}: {e}")
        context["ti"].xcom_push(key="model_auc", value=0)


def check_model_quality(**context):
    auc = context["ti"].xcom_pull(key="model_auc")
    print(f"AUC: {auc}  Threshold: {AUC_THRESHOLD}")
    if auc and float(auc) >= AUC_THRESHOLD:
        return "deploy_model"
    return "model_quality_failed"


def deploy_model(**context):
    model_s3 = context["ti"].xcom_pull(key="model_s3")
    run_date = context["ds_nodash"]
    sm_client = boto3.client("sagemaker", region_name=AWS_REGION)

    model_name    = f"fraud-xgboost-{run_date}"
    endpoint_name = "fraud-detection-endpoint"

    # Create model
    sm_client.create_model(
        ModelName        = model_name,
        PrimaryContainer = {
            "Image":           "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-xgboost:1.7-1",
            "ModelDataUrl":    model_s3,
            "Environment":     {}
        },
        ExecutionRoleArn = SAGEMAKER_ROLE_ARN,
    )

    # Create/update endpoint config
    config_name = f"fraud-config-{run_date}"
    sm_client.create_endpoint_config(
        EndpointConfigName = config_name,
        ProductionVariants  = [{
            "VariantName":    "primary",
            "ModelName":       model_name,
            "InstanceType":    "ml.t2.medium",
            "InitialInstanceCount": 1,
        }]
    )

    # Create or update endpoint
    try:
        sm_client.describe_endpoint(EndpointName=endpoint_name)
        sm_client.update_endpoint(
            EndpointName       = endpoint_name,
            EndpointConfigName = config_name
        )
        print(f"✅ Updated endpoint: {endpoint_name}")
    except sm_client.exceptions.ClientError:
        sm_client.create_endpoint(
            EndpointName       = endpoint_name,
            EndpointConfigName = config_name
        )
        print(f"✅ Created endpoint: {endpoint_name}")


# ── DAG Definition ────────────────────────────────────────────
with DAG(
    dag_id          = "fraud_detection_pipeline",
    description     = "End-to-end fraud detection MLOps pipeline",
    schedule        = "0 2 * * *",   # daily at 2am
    start_date      = datetime(2026, 6, 1),
    catchup         = False,
    default_args    = default_args,
    tags            = ["mlops", "fraud", "sagemaker"],
) as dag:

    start = EmptyOperator(task_id="start")

    bronze_task = PythonOperator(
        task_id         = "bronze_ingestion",
        python_callable = run_bronze,
    )

    silver_task = PythonOperator(
        task_id         = "silver_cleaning",
        python_callable = run_silver,
    )

    gold_task = PythonOperator(
        task_id         = "gold_features",
        python_callable = run_gold,
    )

    export_task = PythonOperator(
        task_id         = "export_to_s3",
        python_callable = run_export,
    )

    training_task = PythonOperator(
        task_id         = "sagemaker_training",
        python_callable = launch_sagemaker_training,
    )

    evaluate_task = PythonOperator(
        task_id         = "evaluate_model",
        python_callable = evaluate_model,
    )

    quality_check = BranchPythonOperator(
        task_id         = "quality_check",
        python_callable = check_model_quality,
    )

    deploy_task = PythonOperator(
        task_id         = "deploy_model",
        python_callable = deploy_model,
    )

    model_quality_failed = EmptyOperator(
        task_id = "model_quality_failed"
    )

    end = EmptyOperator(
        task_id          = "end",
        trigger_rule     = "none_failed_min_one_success"
    )

    # ── Pipeline flow ─────────────────────────────────────────
    start >> bronze_task >> silver_task >> gold_task >> export_task
    export_task >> training_task >> evaluate_task >> quality_check
    quality_check >> deploy_task >> end
    quality_check >> model_quality_failed >> end
