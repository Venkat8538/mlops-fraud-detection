# MLOps Fraud Detection — Project Context for Claude

## Project Overview
End-to-end MLOps pipeline for fraud detection on AWS.
Uses Databricks for data ingestion/feature engineering, SageMaker for model training/serving, Airflow for orchestration.

## AWS Account
- Account ID: `482227257362`
- Region: `us-east-1`
- Databricks workspace: `https://dbc-c586aafa-13e2.cloud.databricks.com`
- GitHub repo: `https://github.com/Venkat8538/mlops-fraud-detection`

## Architecture

```
Databricks → Bronze/Silver/Gold (Delta Lake on S3)
Airflow (EC2) → orchestrates the full pipeline daily at 2am
SageMaker → trains XGBoost fraud classifier, serves endpoint
MLflow (Databricks built-in) → experiment tracking
GitHub Actions → CI/CD via OIDC (no AWS keys stored)
```

## Infrastructure Layout

```
terraform/environments/
  └── dev/                      ← AWS dev account
        ├── foundation/         ← KMS keys (apply first, rarely changes)
        ├── mlops-network/      ← VPC, subnets (mlops-dev-vpc)
        ├── databricks-iam/     ← IAM roles for Databricks
        ├── sagemaker-iam/      ← IAM role for SageMaker training jobs
        ├── github-oidc/        ← OIDC for GitHub Actions (no AWS keys)
        └── airflow-ec2/        ← EC2 t3.medium — destroy when idle

terraform/modules/
  ├── kms/        ← 5 CMKs (eks, s3, ebs, secrets-manager, cloudwatch)
  ├── networking/ ← VPC module (not used directly — mlops-network uses inline)
  ├── s3/         ← 6 S3 buckets (bronze, silver, gold, mlflow-store, spark, tf-state)
  ├── iam/        ← EKS/JupyterHub IAM (future use)
  └── databricks/ ← Databricks cross-account + instance profile roles
```

## S3 Buckets
| Bucket | Purpose |
|--------|---------|
| `mlops-dev-bronze` | Raw ingested transaction data |
| `mlops-dev-silver` | Cleaned/standardized data |
| `mlops-dev-gold` | 30 engineered ML features |
| `mlops-dev-mlflow-store` | MLflow artifacts + SageMaker training data/output |
| `mlops-dev-spark` | Spark temp/shuffle (7-day expiry) |
| `mlops-dev-tf-state` | Terraform remote state |

## Key IAM Roles
| Role | Purpose |
|------|---------|
| `github-actions-mlops-role` | GitHub Actions OIDC — no AWS keys needed |
| `sagemaker-execution-role` | SageMaker training jobs + endpoints |
| `airflow-ec2-role` | Airflow EC2 instance profile — SageMaker + S3 + SSM |
| `databricks-databricks-cross-account-role6785676` | Databricks EC2 launch |
| `databricks-databricks-cloud-storage-role678566` | Unity Catalog S3 access |

## Databricks Setup
- Unity Catalog storage credential: `saic-s3-credential`
- External locations: `mlops-bronze`, `mlops-silver`, `mlops-gold`
- Schemas: `workspace.bronze`, `workspace.silver`, `workspace.gold`
- Notebooks in Repo: `/Repos/ganjikunta.venkat@gmail.com/mlops-fraud-detection/databricks/notebooks/`
- Cluster: `ganjikunta.venkat@gmail.com's Cluster 2026-05-28 16:20:31`

## Airflow EC2
- Instance type: `t3.medium` (destroy when idle to save ~$32/month)
- AMI: Amazon Linux 2023 (NOT ECS-optimized variant)
- SSH: RSA key only — ED25519 fails on this AMI due to EC2 Instance Connect override
- SSH key: `~/.ssh/test_rsa`
- EC2 Instance ID stored in SSM: `/mlops/airflow/ec2-instance-id`
- Airflow version: `2.6.3-python3.10`
- Default login: `admin` / `admin`
- DAG: `fraud_detection_pipeline` — runs daily at 2am

## Terraform Workflow
```bash
# Deploy order (first time or after destroy)
cd terraform/environments/dev/foundation && terraform apply        # KMS + S3 + IAM
cd terraform/environments/dev/mlops-network && terraform apply    # VPC + subnets
cd terraform/environments/dev/databricks-iam && terraform apply   # Databricks IAM
cd terraform/environments/dev/sagemaker-iam && terraform apply    # SageMaker IAM
cd terraform/environments/dev/github-oidc && terraform apply      # GitHub OIDC
cd terraform/environments/dev/airflow-ec2 && terraform apply      # Airflow EC2 (optional)

# Destroy to save money when idle
cd terraform/environments/dev/airflow-ec2 && terraform destroy    # ~$32/month saved
```

## GitHub Actions Workflows
| Workflow | Trigger | Does |
|----------|---------|------|
| `01-upload-sagemaker-code.yml` | Push to `sagemaker/` | Uploads train.py to S3 |
| `02-terraform.yml` | Push to `terraform/` | Plan + apply foundation |
| `03-sagemaker-training.yml` | Manual | Launches SageMaker training job |
| `04-airflow-deploy.yml` | Push to `airflow/dags/` | SSM git pull on EC2 |

## GitHub Secrets
| Secret | Value |
|--------|-------|
| `DATABRICKS_TOKEN` | Databricks PAT (add manually from Databricks UI) |

No AWS credentials in GitHub — uses OIDC role `github-actions-mlops-role`.

## Known Issues / Quirks
- ED25519 SSH fails on this EC2 AMI — always use RSA key (`~/.ssh/test_rsa`)
- Airflow 2.7+ has logging handler bug — use `2.6.3-python3.10`
- KMS keys cost $1/key/month even when idle — 5 keys = $5/month
- NAT Gateway was removed — private subnets have no internet route
- Databricks workspace is personal (not enterprise) — all paths use personal email

## Cost Summary (when Airflow EC2 running)
```
EC2 t3.medium     ~$30/month
EBS 30GB gp3      ~ $2/month
KMS 5 keys        ~ $5/month
S3 (tiny data)    ~ $1/month
Total             ~$38/month
```
Destroy EC2 when not using: saves ~$32/month instantly.
