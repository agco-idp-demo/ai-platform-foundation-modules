> Copyright 2026 Google. This software is provided as-is, without warranty or representation for any use or purpose. Your use of it is subject to your agreement with Google.

# ML Modeling Tenant Module (`ml-modeling-tenant`)

This Terraform module provisions and configures the core tenant foundation for AGCO AI platform workloads in a flat module layout (`apis.tf`, `storage.tf`, `sa.tf`, `mlflow.tf`). It handles:
1. **GCP API Enablement** (Storage, AI Platform, Secret Manager, IAM, Container Engine).
2. **Parameterized Multi-Bucket Cloud Storage** (`for_each` over `var.storage_buckets` with security guardrails, retention policies, lifecycle rules, CMEK encryption, and label merging).
3. **Parameterized Service Accounts & IAM** (with modular list-of-objects support).
4. **Shared Services GKE Cluster Accessor Identity** (Workload Identity keyless authentication for GKE workloads when `gke_hub_project_id` is configured).
5. **Central MLflow Server Integration & Model Artifact Storage** (`for_each` over `var.mlflow_integrations` for cross-project bucket IAM for central MLflow and `sa-ml-runner` on the model artifacts bucket, plus `mlflow-tracking-uri` Secret Manager container and accessor IAM bindings).

## Prerequisites

- **Terraform**: `>= 1.9.0`
- **Google Cloud Provider (`hashicorp/google`)**: `>= 5.0.0, < 7.0.0`
- **Target GCP Project**: An active tenant GCP project (and optional central shared GKE hub project).

## Included Features

- **ML Platform & Supporting API Enablement (`apis.tf`)**: Activates project services via `for_each = var.apis` with `disable_on_destroy = false` by default.
- **Parameterized Multi-Bucket Cloud Storage (`storage.tf`)**: Provisions `google_storage_bucket.buckets` via `for_each = var.storage_buckets` (default `{}`). Enforces `uniform_bucket_level_access = true`, `public_access_prevention = "enforced"`, and `force_destroy = false` by default; converts `retention_period_days` into seconds (`retention_period_days * 86400`); renders dynamic `lifecycle_rule` blocks with a 7-day `AbortIncompleteMultipartUpload` fallback when `lifecycle_rules` is empty; supports optional CMEK encryption (`kms_key_name`); and merges module-level `var.labels` with per-bucket `labels`.
- **Cluster Accessor & Workload Identities (`sa.tf`)**: Provisions dedicated tenant Google Service Accounts, assigns project-level IAM roles, and binds GKE Workload Identity (`roles/iam.workloadIdentityUser`) to Kubernetes Service Accounts in the tenant namespace on `shared-svc-cluster` when `gke_hub_project_id` is provided.
- **Central MLflow Integration (`mlflow.tf`)**: Provisions MLflow integrations via `for_each = var.mlflow_integrations` (default `{}`). Grants `roles/storage.objectAdmin` on the tenant model artifacts bucket to `central_sa_email` and `ml_runner_sa_account_id` (default `"sa-ml-runner"`), provisions `google_secret_manager_secret` (default `"mlflow-tracking-uri"`) and `google_secret_manager_secret_version` storing `tracking_uri`, and grants `roles/secretmanager.secretAccessor` to `ml_runner_sa_account_id` and `cluster_accessor_sa_account_id` (default `"sa-shared-gke-accessor"`, with automatic fallback to `"sa-cluster-accessor"`).

---

## Usage

```hcl
module "ml_modeling_tenant" {
  source = "../../modules/ml-modeling-tenant"

  project_id         = "prj-ml-vision-defect-test"
  gke_hub_project_id = "prj-ai-platform-hub"
  default_location   = "US"

  labels = {
    cost_center   = "cc-1042"
    business_unit = "precision-ag"
    owner         = "vision-ml-team"
    environment   = "dev"
    project_id    = "prj-ml-vision-defect-test"
    managed_by    = "terraform"
  }

  apis = {
    "storage.googleapis.com"       = {}
    "aiplatform.googleapis.com"    = {}
    "secretmanager.googleapis.com" = {}
    "iam.googleapis.com"           = { disable_on_destroy = true }
  }

  storage_buckets = {
    "raw-images" = {
      storage_class         = "STANDARD"
      retention_period_days = 90
      labels = {
        bucket_purpose = "raw-images"
      }
    }
    "artifacts" = {
      storage_class      = "STANDARD"
      versioning_enabled = true
      labels = {
        bucket_purpose = "artifacts"
      }
    }
    "telemetry" = {
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

  service_accounts = [
    {
      account_id   = "sa-cluster-accessor"
      display_name = "Shared Services GKE Cluster Accessor SA"
      ksa_name     = "ksa-cluster-accessor"
      permissions  = []
    },
    {
      # ksa_name omitted -> defaults to account_id
      account_id   = "sa-ml-runner"
      display_name = "Tenant ML Runner SA"
      permissions  = ["roles/aiplatform.user"]
    }
  ]

  mlflow_integrations = {
    "central" = {
      central_sa_email               = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
      tracking_uri                   = "https://mlflow.platform.agco.internal"
      artifacts_bucket_key           = "artifacts"
      secret_id                      = "mlflow-tracking-uri"
      ml_runner_sa_account_id        = "sa-ml-runner"
      cluster_accessor_sa_account_id = "sa-shared-gke-accessor"
    }
  }
}
```

---

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Target GCP project ID for the ML Modeling tenant | `string` | n/a | yes |
| `gke_hub_project_id` | GCP project ID hosting the central GKE cluster (leave empty to skip GKE Workload Identity bindings) | `string` | `""` | no |
| `tenant_namespace` | Kubernetes namespace for tenant workloads (defaults to `workspace-<project_id>`) | `string` | `""` | no |
| `apis` | Map of GCP APIs to enable, keyed by service name. Each value: `{ disable_on_destroy = bool, disable_dependent_services = bool }` (both default `false`) | `map(object)` | `{}` | no |
| `service_accounts` | List of service accounts: `account_id`, optional `display_name`/`description`, optional `ksa_name` (defaults to `account_id`), optional `permissions` list | `list(object)` | `[]` | no |
| `default_location` | Default GCS location applied when a bucket does not specify a location | `string` | `"US"` | no |
| `labels` | Module-level GCP labels merged onto all provisioned storage buckets and secrets (can be extended or overridden per resource) | `map(string)` | `{}` | no |
| `storage_buckets` | Map of GCS bucket configurations keyed by logical bucket identifier. Defaults to `{}` (no buckets provisioned) | `map(object({...}))` | `{}` | no |
| `mlflow_integrations` | Map of Central MLflow integration configurations keyed by logical integration identifier (`central_sa_email`, `tracking_uri`, optional `artifacts_bucket_key`, `artifacts_bucket_name`, `secret_id`, `ml_runner_sa_account_id`, `cluster_accessor_sa_account_id`, `labels`). Defaults to `{}` | `map(object({...}))` | `{}` | no |

---

## Outputs

| Name | Description |
|------|-------------|
| `project_id` | Target GCP project ID |
| `enabled_apis` | List of enabled APIs |
| `tenant_namespace` | Resolved Kubernetes namespace |
| `service_accounts` | Map keyed by `account_id` → `{ email, member, id, unique_id, display_name, ksa_name, workload_identity_member }` |
| `workload_identity_members` | Map keyed by `account_id` → Workload Identity principal string |
| `buckets` | Map of provisioned `google_storage_bucket` resources keyed by logical bucket key |
| `bucket_names` | Map of logical bucket keys to provisioned GCS bucket names |
| `bucket_urls` | Map of logical bucket keys to GCS bucket URLs (`gs://<bucket_name>`) |
| `bucket_self_links` | Map of logical bucket keys to GCS bucket self-links |
| `mlflow_artifact_roots` | Map of logical MLflow integration keys to GCS artifact root URIs (`gs://<bucket>/`) |
| `mlflow_secret_ids` | Map of logical MLflow integration keys to Secret Manager secret resource IDs (`projects/<project>/secrets/<secret_id>`) |
| `mlflow_artifact_root` | Primary GCS artifact root URI (`gs://<bucket>/`) for MLflow model artifacts when configured, else `null` |
| `mlflow_secret_id` | Resource ID of the primary MLflow tracking URI secret in Secret Manager when provisioned, else `null` |

---

## Testing

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test
```

---

## License

Copyright 2026 Google. This software is provided as-is, without warranty or representation for any use or purpose. Your use of it is subject to your agreement with Google.
