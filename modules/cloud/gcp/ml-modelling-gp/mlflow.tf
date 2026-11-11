# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

# Normalize and resolve per-integration references (target artifacts bucket,
# workload runner SA, and GKE cluster accessor SA) for each entry in var.mlflow_integrations.
locals {
  resolved_mlflow_configs = {
    for k, cfg in var.mlflow_integrations : k => {
      # Pass through normalized configuration attributes and merge module + per-integration labels.
      central_sa_email     = trimspace(cfg.central_sa_email)
      tracking_uri         = trimspace(cfg.tracking_uri)
      secret_id            = cfg.secret_id
      artifacts_bucket_key = cfg.artifacts_bucket_key
      labels               = merge(var.labels, cfg.labels)

      # Resolve the target model artifacts bucket name from an explicit override if provided,
      # otherwise look up the bucket managed in storage.tf via artifacts_bucket_key.
      resolved_artifacts_bucket_name = cfg.artifacts_bucket_name != "" ? cfg.artifacts_bucket_name : (
        contains(keys(var.storage_buckets), cfg.artifacts_bucket_key) ? google_storage_bucket.buckets[cfg.artifacts_bucket_key].name : null
      )
      has_artifacts_bucket = cfg.artifacts_bucket_name != "" || contains(keys(var.storage_buckets), cfg.artifacts_bucket_key)

      # Verify that the configured ML workload runner service account exists in var.service_accounts.
      has_ml_runner_sa = contains(keys(local.service_accounts_map), cfg.ml_runner_sa_account_id)
      ml_runner_sa_id  = cfg.ml_runner_sa_account_id

      # Resolve the GKE cluster accessor service account ID, automatically falling back from
      # the default "sa-shared-gke-accessor" to "sa-cluster-accessor" when the latter is used.
      resolved_cluster_accessor_sa_id = contains(keys(local.service_accounts_map), cfg.cluster_accessor_sa_account_id) ? cfg.cluster_accessor_sa_account_id : (
        cfg.cluster_accessor_sa_account_id == "sa-shared-gke-accessor" && contains(keys(local.service_accounts_map), "sa-cluster-accessor") ? "sa-cluster-accessor" : cfg.cluster_accessor_sa_account_id
      )
    }
  }

  # Select the first integration key alphabetically to populate the primary convenience outputs
  # (mlflow_artifact_root and mlflow_secret_id) when at least one integration is configured.
  primary_mlflow_key = length(keys(local.resolved_mlflow_configs)) > 0 ? sort(keys(local.resolved_mlflow_configs))[0] : null
}

# Grant the central MLflow tracking server service account objectAdmin access on the tenant
# model artifacts bucket so it can read and write model weights and artifacts across projects.
resource "google_storage_bucket_iam_member" "central_mlflow_admin" {
  for_each = local.resolved_mlflow_configs

  bucket = coalesce(each.value.resolved_artifacts_bucket_name, "missing-artifacts-bucket")
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value.central_sa_email}"

  depends_on = [
    google_storage_bucket.buckets,
    google_project_service.services,
  ]

  lifecycle {
    precondition {
      condition     = each.value.has_artifacts_bucket
      error_message = "For mlflow_integrations[\"${each.key}\"], the model artifacts bucket (${each.value.artifacts_bucket_key}) must exist in var.storage_buckets or be overridden via artifacts_bucket_name."
    }
  }
}

# Grant the tenant ML workload runner service account objectAdmin access on the model artifacts
# bucket so training and evaluation jobs can upload and retrieve model artifacts directly.
resource "google_storage_bucket_iam_member" "ml_runner_artifacts_admin" {
  for_each = local.resolved_mlflow_configs

  bucket = coalesce(each.value.resolved_artifacts_bucket_name, "missing-artifacts-bucket")
  role   = "roles/storage.objectAdmin"
  # Use a fallback principal string when the SA is absent from var.service_accounts so Terraform
  # surfaces the lifecycle precondition error cleanly instead of failing with a map index error.
  member = (
    each.value.has_ml_runner_sa
    ? "serviceAccount:${google_service_account.sas[each.value.ml_runner_sa_id].account_id}@${var.project_id}.iam.gserviceaccount.com"
    : "serviceAccount:${each.value.ml_runner_sa_id}@${var.project_id}.iam.gserviceaccount.com"
  )

  depends_on = [
    google_storage_bucket.buckets,
    google_service_account.sas,
    google_project_service.services,
  ]

  lifecycle {
    precondition {
      condition     = each.value.has_artifacts_bucket
      error_message = "For mlflow_integrations[\"${each.key}\"], the model artifacts bucket (${each.value.artifacts_bucket_key}) must exist in var.storage_buckets or be overridden via artifacts_bucket_name."
    }
    precondition {
      condition     = each.value.has_ml_runner_sa
      error_message = "For mlflow_integrations[\"${each.key}\"], ml_runner_sa_account_id (${each.value.ml_runner_sa_id}) must exist in var.service_accounts."
    }
  }
}

# Provision the Secret Manager secret container in the tenant project to store the central
# MLflow tracking server URI with automatic replication and governance labels.
resource "google_secret_manager_secret" "mlflow_uri" {
  for_each = local.resolved_mlflow_configs

  project   = var.project_id
  secret_id = each.value.secret_id
  labels    = each.value.labels

  replication {
    auto {}
  }

  depends_on = [
    google_project_service.services,
  ]
}

# Store the central MLflow tracking server HTTPS endpoint URI as the active secret version.
resource "google_secret_manager_secret_version" "mlflow_uri_version" {
  for_each = local.resolved_mlflow_configs

  secret      = google_secret_manager_secret.mlflow_uri[each.key].id
  secret_data = each.value.tracking_uri
}

# Grant the tenant ML workload runner service account secretAccessor permissions to read
# the MLflow tracking URI secret during training and pipeline execution.
resource "google_secret_manager_secret_iam_member" "mlflow_uri_ml_runner_accessor" {
  for_each = local.resolved_mlflow_configs

  project   = google_secret_manager_secret.mlflow_uri[each.key].project
  secret_id = google_secret_manager_secret.mlflow_uri[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member = (
    each.value.has_ml_runner_sa
    ? "serviceAccount:${google_service_account.sas[each.value.ml_runner_sa_id].account_id}@${var.project_id}.iam.gserviceaccount.com"
    : "serviceAccount:${each.value.ml_runner_sa_id}@${var.project_id}.iam.gserviceaccount.com"
  )

  depends_on = [
    google_service_account.sas,
    google_project_service.services,
  ]

  lifecycle {
    precondition {
      condition     = each.value.has_ml_runner_sa
      error_message = "For mlflow_integrations[\"${each.key}\"], ml_runner_sa_account_id (${each.value.ml_runner_sa_id}) must exist in var.service_accounts."
    }
  }
}

# Grant the shared GKE cluster accessor service account secretAccessor permissions so
# External Secrets Operator or GKE workloads can synchronize the MLflow tracking URI secret.
resource "google_secret_manager_secret_iam_member" "mlflow_uri_cluster_accessor" {
  for_each = local.resolved_mlflow_configs

  project   = google_secret_manager_secret.mlflow_uri[each.key].project
  secret_id = google_secret_manager_secret.mlflow_uri[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member = (
    contains(keys(local.service_accounts_map), each.value.resolved_cluster_accessor_sa_id)
    ? "serviceAccount:${google_service_account.sas[each.value.resolved_cluster_accessor_sa_id].account_id}@${var.project_id}.iam.gserviceaccount.com"
    : "serviceAccount:${each.value.resolved_cluster_accessor_sa_id}@${var.project_id}.iam.gserviceaccount.com"
  )

  depends_on = [
    google_service_account.sas,
    google_project_service.services,
  ]

  lifecycle {
    precondition {
      condition     = contains(keys(local.service_accounts_map), each.value.resolved_cluster_accessor_sa_id)
      error_message = "For mlflow_integrations[\"${each.key}\"], cluster_accessor_sa_account_id (${each.value.resolved_cluster_accessor_sa_id}) must exist in var.service_accounts."
    }
  }
}
