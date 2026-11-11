# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

output "project_id" {
  description = "Target GCP project ID."
  value       = var.project_id
}

output "enabled_apis" {
  description = "List of enabled APIs."
  value       = [for k, v in google_project_service.services : v.service]
}

output "service_accounts" {
  description = "Map of created service accounts, keyed by account_id."
  value = {
    for k, v in google_service_account.sas : k => {
      email                    = v.email
      member                   = v.member
      id                       = v.id
      unique_id                = v.unique_id
      display_name             = v.display_name
      ksa_name                 = local.service_accounts_map[k].ksa_name
      workload_identity_member = local.workload_identity_members[k]
    }
  }
}

output "tenant_namespace" {
  description = "Resolved Kubernetes namespace used for Workload Identity bindings."
  value       = local.resolved_tenant_namespace
}

output "workload_identity_members" {
  description = "Map of Workload Identity member principal strings, keyed by account_id."
  value       = local.workload_identity_members
}

# --- Cloud Storage Bucket Outputs ---

output "buckets" {
  description = "Map of provisioned google_storage_bucket resources keyed by logical bucket key."
  value       = google_storage_bucket.buckets
}

output "bucket_names" {
  description = "Map of logical bucket keys to provisioned GCS bucket names."
  value       = { for k, b in google_storage_bucket.buckets : k => b.name }
}

output "bucket_urls" {
  description = "Map of logical bucket keys to GCS bucket URLs (gs://<bucket_name>)."
  value       = { for k, b in google_storage_bucket.buckets : k => "gs://${b.name}" }
}

output "bucket_self_links" {
  description = "Map of logical bucket keys to GCS bucket self-links."
  value       = { for k, b in google_storage_bucket.buckets : k => "https://www.googleapis.com/storage/v1/b/${b.name}" }
}

# --- Central MLflow Server Integration & Model Artifact Storage Outputs ---

output "mlflow_artifact_roots" {
  description = "Map of logical MLflow integration keys to GCS artifact root URIs (gs://<bucket>/)."
  value = {
    for k, v in local.resolved_mlflow_configs :
    k => v.has_artifacts_bucket ? "gs://${v.resolved_artifacts_bucket_name}/" : null
  }
}

output "mlflow_secret_ids" {
  description = "Map of logical MLflow integration keys to Secret Manager secret resource IDs (projects/<project>/secrets/<secret_id>)."
  value = {
    for k, s in google_secret_manager_secret.mlflow_uri :
    k => "projects/${s.project}/secrets/${s.secret_id}"
  }
}

output "mlflow_artifact_root" {
  description = "The primary GCS artifact root URI (gs://<bucket>/) for MLflow model artifacts when an MLflow integration is configured and the artifacts bucket is available, else null."
  value       = local.primary_mlflow_key != null ? (local.resolved_mlflow_configs[local.primary_mlflow_key].has_artifacts_bucket ? "gs://${local.resolved_mlflow_configs[local.primary_mlflow_key].resolved_artifacts_bucket_name}/" : null) : null
}

output "mlflow_secret_id" {
  description = "Resource ID of the primary MLflow tracking URI secret in Secret Manager (projects/<project>/secrets/<secret_id>) when provisioned, else null."
  value       = local.primary_mlflow_key != null ? "projects/${google_secret_manager_secret.mlflow_uri[local.primary_mlflow_key].project}/secrets/${google_secret_manager_secret.mlflow_uri[local.primary_mlflow_key].secret_id}" : null
}
