# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

project_id         = "prj-t-demo-goldenpath-osxq"
region             = "us-east4"
gke_hub_project_id = ""

apis = {
  "storage.googleapis.com"       = {}
  "aiplatform.googleapis.com"    = {}
  "secretmanager.googleapis.com" = {}
  "iam.googleapis.com"           = {}
  "container.googleapis.com"     = {}
}

service_accounts = [
  {
    account_id   = "sa-cluster-accessor"
    display_name = "Shared Services GKE Cluster Accessor SA"
    description  = "Dedicated Google Service Account for tenant workloads executing on the shared GKE cluster via Workload Identity keyless authentication."
    ksa_name     = "ksa-cluster-accessor"
    permissions  = []
  },
  {
    account_id   = "sa-ml-runner"
    display_name = "Tenant ML Runner SA"
    description  = "Dedicated Google Service Account for tenant ML model training, evaluation, and pipeline runner execution."
    ksa_name     = "ksa-ml-runner"
    permissions  = ["roles/aiplatform.user"]
  }
]

default_location = "US"

# Module-level governance and FinOps cost-allocation labels applied to all tenant storage buckets.
labels = {
  cost_center   = "ai-platform"
  business_unit = "ml-platform"
  owner         = "platform-engineering"
  environment   = "dev"
  project_id    = "prj-t-demo-goldenpath-osxq"
  managed_by    = "terraform"
}

# Canonical ML modeling tenant storage buckets:
# - raw-images: 90-day retention policy to protect ingested training datasets from premature deletion.
# - artifacts: object versioning enabled to preserve model weights and evaluation history.
# - telemetry: lifecycle transition to COLDLINE after 90 days to reduce long-term storage costs.
storage_buckets = {
  "raw-images" = {
    location              = "US"
    storage_class         = "STANDARD"
    retention_period_days = 90
    labels = {
      bucket_purpose = "raw-images"
    }
  }
  "artifacts" = {
    location           = "US"
    storage_class      = "STANDARD"
    versioning_enabled = true
    labels = {
      bucket_purpose = "artifacts"
    }
  }
  "telemetry" = {
    location      = "US"
    storage_class = "STANDARD"
    labels = {
      bucket_purpose = "telemetry"
    }
    lifecycle_rules = [
      {
        action = {
          type          = "SetStorageClass"
          storage_class = "COLDLINE"
        }
        condition = {
          age = 90
        }
      },
      {
        action = {
          type = "AbortIncompleteMultipartUpload"
        }
        condition = {
          age = 7
        }
      }
    ]
  }
}

# Central MLflow server integration configurations keyed by logical integration identifier.
# Defaults to an empty map ({}) when MLflow integration is not enabled.
# Example when enabled:
# mlflow_integrations = {
#   "central" = {
#     central_sa_email               = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
#     tracking_uri                   = "https://mlflow.platform.agco.internal"
#     artifacts_bucket_key           = "artifacts"
#     artifacts_bucket_name          = ""
#     secret_id                      = "mlflow-tracking-uri"
#     ml_runner_sa_account_id        = "sa-ml-runner"
#     cluster_accessor_sa_account_id = "sa-shared-gke-accessor"
#   }
# }
mlflow_integrations = {}
