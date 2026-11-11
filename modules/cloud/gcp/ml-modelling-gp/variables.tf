# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

variable "project_id" {
  type        = string
  description = "Target GCP project ID for the ML Modeling tenant."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id variable must be a valid GCP project ID (6-30 characters, lowercase letters, digits, and hyphens)."
  }
}

variable "gke_hub_project_id" {
  type        = string
  description = "GCP project ID hosting the shared central GKE cluster (shared-svc-cluster). Leave empty to skip GKE Workload Identity bindings."
  default     = ""
}

variable "tenant_namespace" {
  type        = string
  description = "Kubernetes namespace for the tenant workloads. Defaults to workspace-<project_id> if empty."
  default     = ""
}

variable "apis" {
  type = map(object({
    disable_on_destroy         = optional(bool, false)
    disable_dependent_services = optional(bool, false)
  }))
  description = "Map of Google Cloud APIs to enable in the project, keyed by service name. Each value controls per-service disable behaviour on destroy."
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
  description = "List of service account definitions, KSA names, and project IAM permissions. ksa_name defaults to account_id when empty."
  default     = []

  validation {
    condition     = length(var.service_accounts) == length(distinct([for sa in var.service_accounts : sa.account_id]))
    error_message = "Each service account must have a unique account_id."
  }
}

# --- Cloud Storage Bucket & Resource Labeling Configuration ---

variable "default_location" {
  type        = string
  description = "Default GCS location (region, dual-region, or multi-region) applied when a bucket does not specify a location."
  default     = "US"
  nullable    = false

  validation {
    condition     = length(trimspace(var.default_location)) > 0
    error_message = "The default_location must be a non-empty GCP region or multi-region string."
  }
}

variable "labels" {
  type        = map(string)
  description = "Module-level GCP labels merged onto all provisioned storage buckets (can be extended or overridden per bucket)."
  default     = {}
  nullable    = false

  validation {
    condition = length(var.labels) <= 64 && alltrue([
      for k, v in var.labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{1,63}$", v))
    ])
    error_message = "All labels keys and values must adhere to GCP label formatting rules (at most 64 labels, non-empty lowercase alphanumeric, hyphens, and underscores)."
  }
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
  description = "Map of GCS bucket configurations keyed by logical bucket identifier. Defaults to an empty map."
  default     = {}
  nullable    = false

  # Enforce GCS bucket naming rules (RFC 1123 / GCS constraints, no reserved "goog"/"google" prefixes or substrings)
  # and ensure no two logical bucket keys resolve to the same global GCS bucket name.
  validation {
    condition = alltrue([
      for k, b in var.storage_buckets :
      can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", k)) &&
      !strcontains(k, "google") &&
      !strcontains(k, "g00gle") &&
      can(regex("^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$", coalesce(b.name, "${var.project_id}-${k}"))) &&
      !strcontains(coalesce(b.name, "${var.project_id}-${k}"), "..") &&
      !startswith(coalesce(b.name, "${var.project_id}-${k}"), "goog") &&
      !strcontains(coalesce(b.name, "${var.project_id}-${k}"), "google") &&
      !strcontains(coalesce(b.name, "${var.project_id}-${k}"), "g00gle")
      ]) && length(var.storage_buckets) == length(distinct([
        for k, b in var.storage_buckets : coalesce(b.name, "${var.project_id}-${k}")
    ]))
    error_message = "Bucket keys and effective bucket names must be unique, valid GCS bucket names (3-63 lowercase letters, numbers, hyphens, underscores, or dots; starting and ending with alphanumeric characters; not containing '..', 'google', or 'g00gle', or starting with 'goog')."
  }

  # Restrict bucket storage_class to standard GCP Cloud Storage tiers.
  validation {
    condition = alltrue([
      for k, b in var.storage_buckets :
      contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], coalesce(b.storage_class, "STANDARD"))
    ])
    error_message = "Each bucket storage_class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }

  # GCP bucket retention policies require whole-day integers up to 24,855 days (~68 years),
  # and a retention lock cannot be enabled unless a retention period is actually defined.
  validation {
    condition = alltrue([
      for k, b in var.storage_buckets :
      coalesce(b.retention_period_days, 1) > 0 &&
      floor(coalesce(b.retention_period_days, 1)) == coalesce(b.retention_period_days, 1) &&
      coalesce(b.retention_period_days, 1) <= 24855 &&
      (!coalesce(b.retention_is_locked, false) || b.retention_period_days != null)
    ])
    error_message = "When specified, retention_period_days must be a whole integer between 1 and 24855 inclusive, and retention_is_locked cannot be true when retention_period_days is null."
  }

  # Validate Cloud KMS key resource ID format when customer-managed encryption (CMEK) is configured.
  validation {
    condition = alltrue([
      for k, b in var.storage_buckets :
      b.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", trimspace(coalesce(b.kms_key_name, ""))))
    ])
    error_message = "When specified, kms_key_name must be a valid Cloud KMS cryptoKey resource ID (projects/<project>/locations/<location>/keyRings/<keyring>/cryptoKeys/<key>)."
  }

  # Validate lifecycle rule action types, required action-specific attributes (target storage_class
  # for SetStorageClass, age for AbortIncompleteMultipartUpload), and ensure at least one non-empty condition is set.
  validation {
    condition = alltrue(flatten([
      for k, b in var.storage_buckets : [
        for rule in coalesce(b.lifecycle_rules, []) :
        contains(["Delete", "SetStorageClass", "AbortIncompleteMultipartUpload"], rule.action.type) && (
          rule.action.type != "SetStorageClass" ||
          contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], coalesce(rule.action.storage_class, "INVALID"))
          ) && (
          rule.action.type != "AbortIncompleteMultipartUpload" ||
          rule.condition.age != null
          ) && (
          rule.condition.age == null || (coalesce(rule.condition.age, 0) >= 0 && floor(coalesce(rule.condition.age, 0)) == coalesce(rule.condition.age, 0))
          ) && (
          rule.condition.num_newer_versions == null || (coalesce(rule.condition.num_newer_versions, 0) >= 0 && floor(coalesce(rule.condition.num_newer_versions, 0)) == coalesce(rule.condition.num_newer_versions, 0))
          ) && (
          rule.condition.days_since_noncurrent_time == null || (coalesce(rule.condition.days_since_noncurrent_time, 0) >= 0 && floor(coalesce(rule.condition.days_since_noncurrent_time, 0)) == coalesce(rule.condition.days_since_noncurrent_time, 0))
          ) && (
          rule.condition.with_state == null || contains(["LIVE", "ARCHIVED", "ANY"], coalesce(rule.condition.with_state, "INVALID"))
          ) && anytrue([
            rule.condition.age != null,
            rule.condition.created_before != null,
            rule.condition.with_state != null,
            length(coalesce(rule.condition.matches_storage_class, [])) > 0,
            length(coalesce(rule.condition.matches_prefix, [])) > 0,
            length(coalesce(rule.condition.matches_suffix, [])) > 0,
            rule.condition.num_newer_versions != null,
            rule.condition.days_since_noncurrent_time != null,
        ])
      ]
    ]))
    error_message = "Lifecycle rule action.type must be Delete, SetStorageClass, or AbortIncompleteMultipartUpload; SetStorageClass rules must specify a valid target storage_class; AbortIncompleteMultipartUpload rules must specify condition.age; numeric conditions must be non-negative whole integers; with_state must be LIVE, ARCHIVED, or ANY; and every rule must specify at least one non-empty condition attribute."
  }

  # Validate per-bucket label formatting and ensure merged module + bucket labels stay within GCP's 64-label limit.
  validation {
    condition = alltrue(flatten([
      for k, b in var.storage_buckets : concat(
        [length(merge(var.labels, coalesce(b.labels, {}))) <= 64],
        [
          for label_k, label_v in coalesce(b.labels, {}) :
          can(regex("^[a-z][a-z0-9_-]{0,62}$", label_k)) && can(regex("^[a-z0-9_-]{1,63}$", label_v))
        ]
      )
    ]))
    error_message = "Per-bucket labels must use valid non-empty GCP label keys and values (lowercase alphanumeric, hyphens, and underscores) and total merged labels per bucket must not exceed 64."
  }
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

  # Validate integration map keys and ensure each entry resolves to a valid, unique Secret Manager secret_id.
  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z0-9][a-z0-9_-]{0,61}[a-z0-9]?$", k)) &&
      can(regex("^[a-zA-Z0-9_-]{1,255}$", cfg.secret_id))
    ]) && length(var.mlflow_integrations) == length(distinct([for k, cfg in var.mlflow_integrations : cfg.secret_id]))
    error_message = "Each mlflow_integrations key must be a valid lowercase identifier, and each secret_id must be a unique, valid Secret Manager secret ID (1-255 alphanumeric characters, hyphens, or underscores)."
  }

  # Validate central MLflow service account email format.
  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z0-9][a-z0-9._-]*[a-z0-9]@[a-z0-9][a-z0-9.-]*\\.gserviceaccount\\.com$", trimspace(cfg.central_sa_email))) &&
      !strcontains(trimspace(cfg.central_sa_email), "..")
    ])
    error_message = "Each mlflow_integrations.central_sa_email must be a valid lowercase GCP service account email ending in .gserviceaccount.com."
  }

  # Validate central MLflow tracking URI format (HTTPS URL, valid hostname, optional TCP port 1-65535, no whitespace).
  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^https://[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*(:([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(/[^\\s]*)?$", trimspace(cfg.tracking_uri)))
    ])
    error_message = "Each mlflow_integrations.tracking_uri must be a valid HTTPS URL (starting with https://, valid hostname, optional port 1-65535, and no whitespace)."
  }

  # Validate artifacts_bucket_key and optional artifacts_bucket_name against GCS bucket naming rules.
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

  # Validate workload runner and cluster accessor service account IDs.
  validation {
    condition = alltrue([
      for k, cfg in var.mlflow_integrations :
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", cfg.ml_runner_sa_account_id)) &&
      can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", cfg.cluster_accessor_sa_account_id))
    ])
    error_message = "Each mlflow_integrations.ml_runner_sa_account_id and cluster_accessor_sa_account_id must be a valid GCP service account ID (6-30 lowercase alphanumeric characters and hyphens)."
  }

  # Validate per-integration label formatting and ensure merged module + integration labels stay within GCP's 64-label limit.
  validation {
    condition = alltrue(flatten([
      for k, cfg in var.mlflow_integrations : concat(
        [length(merge(var.labels, cfg.labels)) <= 64],
        [
          for label_k, label_v in cfg.labels :
          can(regex("^[a-z][a-z0-9_-]{0,62}$", label_k)) && can(regex("^[a-z0-9_-]{1,63}$", label_v))
        ]
      )
    ]))
    error_message = "Per-integration labels in mlflow_integrations must use valid non-empty GCP label keys and values (lowercase alphanumeric, hyphens, and underscores) and total merged labels per secret must not exceed 64."
  }
}
