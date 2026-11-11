# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

variable "project_id" {
  type        = string
  description = "Target GCP Project ID for the example."
  default     = "prj-t-demo-goldenpath-osxq"
}

variable "region" {
  type        = string
  description = "Target GCP Region for tenant resources."
  default     = "us-east4"
}

variable "gke_hub_project_id" {
  type        = string
  description = "Hub GCP Project ID for shared GKE cluster. Leave empty to skip GKE Workload Identity bindings."
  default     = ""
}

variable "apis" {
  type = map(object({
    disable_on_destroy         = optional(bool, false)
    disable_dependent_services = optional(bool, false)
  }))
  description = "Map of Google Cloud APIs to enable, keyed by service name."
  default     = {}
}

variable "service_accounts" {
  type = list(object({
    account_id   = string
    display_name = optional(string, "")
    description  = optional(string, "")
    ksa_name     = optional(string, "")
    permissions  = optional(list(string), [])
  }))
  description = "List of service accounts, KSA names, and IAM permissions."
  default     = []
}

variable "default_location" {
  type        = string
  description = "Default GCS location applied when a bucket does not specify a location."
  default     = "US"
}

variable "labels" {
  type        = map(string)
  description = "Module-level GCP labels merged onto all provisioned storage buckets."
  default     = {}
}

variable "storage_buckets" {
  type = map(object({
    name                  = optional(string)
    location              = optional(string)
    storage_class         = optional(string, "STANDARD")
    force_destroy         = optional(bool, false)
    versioning_enabled    = optional(bool, false)
    retention_period_days = optional(number)
    retention_is_locked   = optional(bool, false)
    kms_key_name          = optional(string)
    labels                = optional(map(string), {})
    lifecycle_rules = optional(list(object({
      action = object({
        type          = string
        storage_class = optional(string)
      })
      condition = object({
        age                        = optional(number)
        created_before             = optional(string)
        with_state                 = optional(string)
        matches_storage_class      = optional(list(string))
        matches_prefix             = optional(list(string))
        matches_suffix             = optional(list(string))
        num_newer_versions         = optional(number)
        days_since_noncurrent_time = optional(number)
      })
    })), [])
  }))
  description = "Map of GCS bucket configurations keyed by logical bucket identifier."
  default     = {}
}

# --- Central MLflow Server Integration & Model Artifact Storage Configuration ---

variable "mlflow_integrations" {
  type = map(object({
    central_sa_email               = string
    tracking_uri                   = string
    artifacts_bucket_key           = optional(string, "artifacts")
    artifacts_bucket_name          = optional(string, "")
    secret_id                      = optional(string, "mlflow-tracking-uri")
    ml_runner_sa_account_id        = optional(string, "sa-ml-runner")
    cluster_accessor_sa_account_id = optional(string, "sa-shared-gke-accessor")
    labels                         = optional(map(string), {})
  }))
  description = "Map of Central MLflow integration configurations keyed by logical integration identifier (e.g., \"central\"). Configures cross-project model artifact bucket IAM for central_sa_email and ml_runner_sa_account_id, provisions the Secret Manager secret storing tracking_uri, and binds secretAccessor IAM for ml_runner_sa_account_id and cluster_accessor_sa_account_id (with automatic fallback from sa-shared-gke-accessor to sa-cluster-accessor). Defaults to an empty map."
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z0-9][a-z0-9_-]{0,61}[a-z0-9]?$", k)) &&
      can(regex("^[a-zA-Z0-9_-]{1,255}$", cfg.secret_id))
    ]) && length(var.mlflow_integrations) == length(distinct([for k, cfg in var.mlflow_integrations : cfg.secret_id]))
    error_message = "Each mlflow_integrations key must be a valid lowercase identifier, and each secret_id must be a unique, valid Secret Manager secret ID (1-255 alphanumeric characters, hyphens, or underscores)."
  }

  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]@[a-z0-9][a-z0-9.-]*\\.gserviceaccount\\.com$", trimspace(cfg.central_sa_email))) &&
      !strcontains(trimspace(cfg.central_sa_email), "..")
    ])
    error_message = "Each mlflow_integrations.central_sa_email must be a valid lowercase GCP service account email ending in .gserviceaccount.com."
  }

  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^https://[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*(:([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(/[^\\s]*)?$", trimspace(cfg.tracking_uri)))
    ])
    error_message = "Each mlflow_integrations.tracking_uri must be a valid HTTPS URL (starting with https://, valid hostname, optional port 1-65535, and no whitespace)."
  }

  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations : (
        can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", cfg.artifacts_bucket_key)) &&
        !strcontains(cfg.artifacts_bucket_key, "..") &&
        !strcontains(cfg.artifacts_bucket_key, "google") &&
        !strcontains(cfg.artifacts_bucket_key, "g00gle")
        ) && (
        cfg.artifacts_bucket_name == "" || (
          can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", cfg.artifacts_bucket_name)) &&
          !strcontains(cfg.artifacts_bucket_name, "..") &&
          !startswith(cfg.artifacts_bucket_name, "goog") &&
          !strcontains(cfg.artifacts_bucket_name, "google") &&
          !strcontains(cfg.artifacts_bucket_name, "g00gle")
        )
      )
    ])
    error_message = "Each mlflow_integrations.artifacts_bucket_key and artifacts_bucket_name (when specified) must be valid GCS bucket names (3-63 lowercase letters, numbers, hyphens, underscores, or dots; no gs:// prefix; not containing '..', 'google', or 'g00gle', or starting with 'goog')."
  }

  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", cfg.ml_runner_sa_account_id)) &&
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", cfg.cluster_accessor_sa_account_id))
    ])
    error_message = "Each mlflow_integrations.ml_runner_sa_account_id and cluster_accessor_sa_account_id must be a valid GCP service account ID (6-30 lowercase alphanumeric characters and hyphens)."
  }
}
