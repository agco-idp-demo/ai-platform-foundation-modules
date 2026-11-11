# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

output "project_id" {
  description = "Target GCP project ID."
  value       = module.ml_tenant.project_id
}

output "enabled_apis" {
  description = "List of enabled APIs."
  value       = module.ml_tenant.enabled_apis
}

output "tenant_namespace" {
  description = "Resolved Kubernetes namespace used for Workload Identity bindings."
  value       = module.ml_tenant.tenant_namespace
}

output "service_accounts" {
  description = "Map of created service accounts (email, member, id, unique_id, ksa_name, workload_identity_member), keyed by account_id."
  value       = module.ml_tenant.service_accounts
}

output "workload_identity_members" {
  description = "Map of Workload Identity member principal strings, keyed by account_id."
  value       = module.ml_tenant.workload_identity_members
}

output "buckets" {
  description = "Map of provisioned google_storage_bucket resources keyed by logical bucket key."
  value       = module.ml_tenant.buckets
}

output "bucket_names" {
  description = "Map of logical bucket keys to provisioned GCS bucket names."
  value       = module.ml_tenant.bucket_names
}

output "bucket_urls" {
  description = "Map of logical bucket keys to GCS bucket URLs (gs://<bucket_name>)."
  value       = module.ml_tenant.bucket_urls
}

output "bucket_self_links" {
  description = "Map of logical bucket keys to GCS bucket self-links."
  value       = module.ml_tenant.bucket_self_links
}

output "mlflow_artifact_roots" {
  description = "Map of logical MLflow integration keys to GCS artifact root URIs (gs://<bucket>/)."
  value       = module.ml_tenant.mlflow_artifact_roots
}

output "mlflow_secret_ids" {
  description = "Map of logical MLflow integration keys to Secret Manager secret resource IDs (projects/<project>/secrets/<secret_id>)."
  value       = module.ml_tenant.mlflow_secret_ids
}

output "mlflow_artifact_root" {
  description = "The primary GCS artifact root URI (gs://<bucket>/) for MLflow model artifacts when an MLflow integration is configured and the artifacts bucket is available, else null."
  value       = module.ml_tenant.mlflow_artifact_root
}

output "mlflow_secret_id" {
  description = "Resource ID of the primary MLflow tracking URI secret in Secret Manager (projects/<project>/secrets/<secret_id>) when provisioned, else null."
  value       = module.ml_tenant.mlflow_secret_id
}
