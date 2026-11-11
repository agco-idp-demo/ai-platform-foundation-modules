# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

# Provision tenant Cloud Storage buckets from the parameterized storage_buckets map.
# Enforces uniform bucket-level access (disabling legacy object ACLs) and public access
# prevention across all buckets to maintain tenant data perimeter isolation.
resource "google_storage_bucket" "buckets" {
  for_each = var.storage_buckets

  name                        = coalesce(each.value.name, "${var.project_id}-${each.key}")
  project                     = var.project_id
  location                    = coalesce(try(length(trimspace(each.value.location)) > 0 ? trimspace(each.value.location) : null, null), trimspace(var.default_location))
  storage_class               = coalesce(each.value.storage_class, "STANDARD")
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = coalesce(each.value.force_destroy, false)

  # Merge module-level taxonomy/governance labels with bucket-specific labels,
  # allowing per-bucket labels to extend or override module-level keys.
  labels = merge(var.labels, coalesce(each.value.labels, {}))

  versioning {
    enabled = coalesce(each.value.versioning_enabled, false)
  }

  # GCP retention_policy expects duration in seconds; convert retention_period_days
  # (days * 86,400 seconds/day) only when a positive retention period is configured.
  dynamic "retention_policy" {
    for_each = coalesce(each.value.retention_period_days, 0) > 0 ? [each.value.retention_period_days] : []
    content {
      retention_period = retention_policy.value * 86400
      is_locked        = coalesce(each.value.retention_is_locked, false)
    }
  }

  # Apply caller-defined lifecycle rules when provided; otherwise default to a 7-day
  # AbortIncompleteMultipartUpload rule to prevent storage cost leaks from abandoned uploads.
  dynamic "lifecycle_rule" {
    for_each = length(coalesce(each.value.lifecycle_rules, [])) > 0 ? each.value.lifecycle_rules : [
      {
        action = {
          type          = "AbortIncompleteMultipartUpload"
          storage_class = null
        }
        condition = {
          age                        = 7
          created_before             = null
          with_state                 = null
          matches_storage_class      = null
          matches_prefix             = null
          matches_suffix             = null
          num_newer_versions         = null
          days_since_noncurrent_time = null
        }
      }
    ]
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lifecycle_rule.value.action.storage_class
      }
      condition {
        age                        = lifecycle_rule.value.condition.age
        created_before             = lifecycle_rule.value.condition.created_before
        with_state                 = lifecycle_rule.value.condition.with_state
        matches_storage_class      = lifecycle_rule.value.condition.matches_storage_class
        matches_prefix             = lifecycle_rule.value.condition.matches_prefix
        matches_suffix             = lifecycle_rule.value.condition.matches_suffix
        num_newer_versions         = lifecycle_rule.value.condition.num_newer_versions
        days_since_noncurrent_time = lifecycle_rule.value.condition.days_since_noncurrent_time
      }
    }
  }

  # Buckets use Google-managed encryption keys by default; configure customer-managed
  # encryption (CMEK) only when a Cloud KMS cryptoKey resource ID is supplied.
  dynamic "encryption" {
    for_each = each.value.kms_key_name != null ? (trimspace(each.value.kms_key_name) != "" ? [each.value.kms_key_name] : []) : []
    content {
      default_kms_key_name = trimspace(encryption.value)
    }
  }
}
