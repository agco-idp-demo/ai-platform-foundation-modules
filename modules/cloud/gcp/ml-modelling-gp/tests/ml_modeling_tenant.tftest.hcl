# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

# These are plan-only unit tests with no prior state, so the Google provider never
# calls the API. Supplying a mock access token satisfies provider configuration
# without requiring Application Default Credentials (e.g. in CI).
provider "google" {
  access_token = "mock-access-token"
}

variables {
  project_id         = "prj-ml-vision-test-dev"
  gke_hub_project_id = "prj-ai-platform-hub"
  default_location   = "US"

  labels = {
    cost_center   = "ai-platform"
    business_unit = "ml-platform"
    owner         = "platform-engineering"
    environment   = "dev"
    project_id    = "prj-ml-vision-test-dev"
    managed_by    = "terraform"
  }

  apis = {
    "storage.googleapis.com"       = {}
    "aiplatform.googleapis.com"    = {}
    "secretmanager.googleapis.com" = {}
    "iam.googleapis.com"           = {}
    "container.googleapis.com"     = {}
  }

  service_accounts = [
    {
      account_id = "sa-shared-gke-accessor"
      ksa_name   = "ksa-shared-gke-accessor"
    },
    {
      account_id  = "sa-ml-runner"
      ksa_name    = "ksa-ml-runner"
      permissions = ["roles/aiplatform.user"]
    }
  ]

  storage_buckets = {
    "raw-images" = {
      storage_class         = "STANDARD"
      retention_period_days = 90
      labels = {
        bucket_purpose = "raw-images"
      }
      lifecycle_rules = []
    }
    "artifacts" = {
      storage_class         = "STANDARD"
      versioning_enabled    = true
      retention_period_days = null
      labels = {
        bucket_purpose = "artifacts"
      }
    }
    "telemetry" = {
      location      = "us-central1"
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
            type = "Delete"
          }
          condition = {
            age = 365
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
}

# --- Plan Verification: Default Provisioning, Custom Overrides & Empty Defaults ---

run "verify_ml_modeling_tenant_provisioning" {
  command = plan

  assert {
    condition     = output.tenant_namespace == "workspace-prj-ml-vision-test-dev"
    error_message = "tenant_namespace must default to workspace-<project_id>"
  }

  assert {
    condition     = output.workload_identity_members["sa-shared-gke-accessor"] == "serviceAccount:prj-ai-platform-hub.svc.id.goog[workspace-prj-ml-vision-test-dev/ksa-shared-gke-accessor]"
    error_message = "Cluster Accessor Workload Identity member principal string is incorrect"
  }

  assert {
    condition     = output.workload_identity_members["sa-ml-runner"] == "serviceAccount:prj-ai-platform-hub.svc.id.goog[workspace-prj-ml-vision-test-dev/ksa-ml-runner]"
    error_message = "ML Runner Workload Identity member principal string is incorrect"
  }

  assert {
    condition     = length(google_service_account.sas) == 2
    error_message = "Exactly two service accounts must be planned"
  }

  assert {
    condition     = length(google_project_iam_member.sa_roles) == 1
    error_message = "Exactly one project IAM role binding must be planned"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_bindings) == 2
    error_message = "Each service account must receive a Workload Identity binding when gke_hub_project_id is set"
  }

  assert {
    condition     = length(google_project_service.services) == 5
    error_message = "All five supplied APIs must be enabled"
  }

  assert {
    condition     = google_project_service.services["storage.googleapis.com"].disable_on_destroy == false
    error_message = "disable_on_destroy must default to false"
  }

  assert {
    condition     = google_project_service.services["storage.googleapis.com"].disable_dependent_services == false
    error_message = "disable_dependent_services must default to false"
  }

  assert {
    condition     = length(google_storage_bucket.buckets) == 3 && output.bucket_names["raw-images"] == "prj-ml-vision-test-dev-raw-images" && output.bucket_names["artifacts"] == "prj-ml-vision-test-dev-artifacts" && output.bucket_names["telemetry"] == "prj-ml-vision-test-dev-telemetry"
    error_message = "All three parameterized storage_buckets must be planned directly via google_storage_bucket.buckets with default <project_id>-<key> naming."
  }

  assert {
    condition = alltrue([
      for k, b in google_storage_bucket.buckets :
      b.uniform_bucket_level_access == true &&
      b.public_access_prevention == "enforced" &&
      b.force_destroy == false &&
      b.labels["cost_center"] == "ai-platform" &&
      b.labels["business_unit"] == "ml-platform" &&
      b.labels["owner"] == "platform-engineering" &&
      b.labels["environment"] == "dev" &&
      b.labels["project_id"] == "prj-ml-vision-test-dev" &&
      b.labels["managed_by"] == "terraform" &&
      b.labels["bucket_purpose"] == k
    ])
    error_message = "All provisioned buckets must enforce security guardrails and merge module-level and per-bucket labels."
  }

  assert {
    condition     = google_storage_bucket.buckets["artifacts"].location == "US" && google_storage_bucket.buckets["telemetry"].location == "US-CENTRAL1"
    error_message = "Bucket location must default to var.default_location (US) when omitted and use per-bucket override (US-CENTRAL1) when specified."
  }

  assert {
    condition     = google_storage_bucket.buckets["artifacts"].versioning[0].enabled == true && google_storage_bucket.buckets["raw-images"].versioning[0].enabled == false
    error_message = "Artifacts bucket must enable versioning while raw-images disables it by default."
  }

  assert {
    condition     = google_storage_bucket.buckets["raw-images"].retention_policy[0].retention_period == 7776000 && google_storage_bucket.buckets["raw-images"].retention_policy[0].is_locked == false && length(google_storage_bucket.buckets["artifacts"].retention_policy) == 0
    error_message = "Bucket with retention_period_days = 90 must set retention_period = 7776000 (90 * 86400) and is_locked = false, while retention_period_days = null must omit retention_policy."
  }

  assert {
    condition     = length(google_storage_bucket.buckets["raw-images"].lifecycle_rule) == 1 && one(google_storage_bucket.buckets["raw-images"].lifecycle_rule[0].action).type == "AbortIncompleteMultipartUpload" && one(google_storage_bucket.buckets["raw-images"].lifecycle_rule[0].condition).age == 7
    error_message = "Bucket with empty lifecycle_rules must fall back inline to a 7-day AbortIncompleteMultipartUpload rule."
  }

  assert {
    condition     = length(google_storage_bucket.buckets["telemetry"].lifecycle_rule) == 3 && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[0].action).type == "SetStorageClass" && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[0].action).storage_class == "COLDLINE" && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[0].condition).age == 90 && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[1].action).type == "Delete" && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[1].condition).age == 365 && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[2].action).type == "AbortIncompleteMultipartUpload" && one(google_storage_bucket.buckets["telemetry"].lifecycle_rule[2].condition).age == 7
    error_message = "Telemetry bucket must render custom lifecycle rules including 90-day COLDLINE transition, 365-day Delete, and 7-day AbortIncompleteMultipartUpload."
  }

  assert {
    condition     = output.bucket_urls["raw-images"] == "gs://prj-ml-vision-test-dev-raw-images" && output.bucket_self_links["raw-images"] == "https://www.googleapis.com/storage/v1/b/prj-ml-vision-test-dev-raw-images"
    error_message = "bucket_urls and bucket_self_links outputs must resolve directly from google_storage_bucket.buckets."
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.central_mlflow_admin) == 0 && length(google_storage_bucket_iam_member.ml_runner_artifacts_admin) == 0 && length(google_secret_manager_secret.mlflow_uri) == 0 && length(output.mlflow_artifact_roots) == 0 && length(output.mlflow_secret_ids) == 0 && output.mlflow_artifact_root == null && output.mlflow_secret_id == null
    error_message = "MLflow resources and IAM bindings must not be planned by default when mlflow_integrations is empty."
  }
}

run "verify_ml_modeling_tenant_custom_overrides" {
  command = plan

  variables {
    tenant_namespace = "custom-namespace"
    default_location = "us-central1"

    labels = {
      cost_center = "cc-9000"
      workload    = "computer-vision"
    }

    storage_buckets = {
      "raw-images" = {
        name                  = "bkt-team-alpha-raw-images"
        storage_class         = "NEARLINE"
        force_destroy         = true
        retention_period_days = 90
        retention_is_locked   = true
        kms_key_name          = null
        labels = {
          cost_center = "cc-override-9999"
          tier        = "bronze"
        }
      }
      "artifacts" = {
        name               = "bkt-team-alpha-artifacts"
        versioning_enabled = true
        kms_key_name       = "projects/prj-sec-kms/locations/us/keyRings/kr-ml/cryptoKeys/cmek-artifacts"
        lifecycle_rules = [
          {
            action = {
              type = "Delete"
            }
            condition = {
              with_state                 = "ARCHIVED"
              num_newer_versions         = 3
              days_since_noncurrent_time = 30
              matches_prefix             = ["logs/"]
              matches_suffix             = [".tmp"]
              matches_storage_class      = ["STANDARD"]
              created_before             = "2026-01-01"
            }
          }
        ]
      }
    }

    apis = {
      "storage.googleapis.com" = {
        disable_on_destroy         = true
        disable_dependent_services = true
      }
      "iam.googleapis.com" = {}
    }

    service_accounts = [
      {
        account_id = "sa-custom-accessor"
        ksa_name   = "ksa-custom-accessor"
      },
      {
        # ksa_name omitted: must default to account_id
        account_id = "sa-runner-custom"
      }
    ]
  }

  assert {
    condition     = output.tenant_namespace == "custom-namespace"
    error_message = "Custom tenant_namespace override not applied"
  }

  assert {
    condition     = output.workload_identity_members["sa-custom-accessor"] == "serviceAccount:prj-ai-platform-hub.svc.id.goog[custom-namespace/ksa-custom-accessor]"
    error_message = "Custom ksa_name Workload Identity member principal for cluster accessor is incorrect"
  }

  assert {
    condition     = output.workload_identity_members["sa-runner-custom"] == "serviceAccount:prj-ai-platform-hub.svc.id.goog[custom-namespace/sa-runner-custom]"
    error_message = "ksa_name must default to account_id when omitted"
  }

  assert {
    condition     = length(google_project_service.services) == 2
    error_message = "Custom apis map must enable exactly two services"
  }

  assert {
    condition     = google_project_service.services["storage.googleapis.com"].disable_on_destroy == true && google_project_service.services["storage.googleapis.com"].disable_dependent_services == true
    error_message = "Per-API disable_on_destroy / disable_dependent_services overrides not applied"
  }

  assert {
    condition     = google_project_service.services["iam.googleapis.com"].disable_on_destroy == false
    error_message = "Per-API disable flags must default to false when omitted"
  }

  assert {
    condition     = length(output.buckets) == 2 && output.bucket_names["raw-images"] == "bkt-team-alpha-raw-images" && output.bucket_names["artifacts"] == "bkt-team-alpha-artifacts"
    error_message = "Custom storage_buckets override must provision only the specified buckets."
  }

  assert {
    condition     = output.buckets["raw-images"].location == "US-CENTRAL1" && output.buckets["raw-images"].storage_class == "NEARLINE" && output.buckets["raw-images"].force_destroy == true && output.bucket_urls["raw-images"] == "gs://bkt-team-alpha-raw-images" && output.bucket_self_links["raw-images"] == "https://www.googleapis.com/storage/v1/b/bkt-team-alpha-raw-images"
    error_message = "Custom storage_buckets must resolve default_location, storage_class, force_destroy, bucket_names, bucket_urls, and bucket_self_links accurately."
  }

  assert {
    condition     = output.buckets["raw-images"].retention_policy[0].retention_period == 7776000 && output.buckets["raw-images"].retention_policy[0].is_locked == true && output.buckets["raw-images"].labels["cost_center"] == "cc-override-9999" && output.buckets["raw-images"].labels["workload"] == "computer-vision" && output.buckets["raw-images"].labels["tier"] == "bronze"
    error_message = "Custom storage_buckets must apply retention_period in seconds, retention_is_locked, and allow per-bucket labels to override colliding module-level labels."
  }

  assert {
    condition     = one(output.buckets["artifacts"].lifecycle_rule[0].condition).with_state == "ARCHIVED" && one(output.buckets["artifacts"].lifecycle_rule[0].condition).num_newer_versions == 3 && one(output.buckets["artifacts"].lifecycle_rule[0].condition).days_since_noncurrent_time == 30 && one(output.buckets["artifacts"].lifecycle_rule[0].condition).created_before == "2026-01-01" && contains(one(output.buckets["artifacts"].lifecycle_rule[0].condition).matches_prefix, "logs/") && contains(one(output.buckets["artifacts"].lifecycle_rule[0].condition).matches_suffix, ".tmp") && contains(one(output.buckets["artifacts"].lifecycle_rule[0].condition).matches_storage_class, "STANDARD")
    error_message = "Custom lifecycle_rules must propagate non-age condition attributes (with_state, num_newer_versions, days_since_noncurrent_time, created_before, matches_prefix, matches_suffix, matches_storage_class)."
  }

  assert {
    condition     = length(google_storage_bucket.buckets["raw-images"].encryption) == 0 && google_storage_bucket.buckets["artifacts"].encryption[0].default_kms_key_name == "projects/prj-sec-kms/locations/us/keyRings/kr-ml/cryptoKeys/cmek-artifacts"
    error_message = "Google-managed encryption must be used when kms_key_name is null, and CMEK encryption block must be rendered when kms_key_name is set."
  }
}

run "verify_empty_defaults_and_optional_gke_hub" {
  command = plan

  variables {
    gke_hub_project_id = ""
    apis               = {}
    service_accounts = [
      {
        account_id = "sa-ml-runner"
      }
    ]
    storage_buckets = {}
  }

  assert {
    condition     = length(google_project_service.services) == 0
    error_message = "No APIs should be enabled when the apis map is empty (module default)"
  }

  assert {
    condition     = length(google_service_account.sas) == 1
    error_message = "Service account must still be provisioned when gke_hub_project_id is empty"
  }

  assert {
    condition     = length(google_service_account_iam_member.workload_identity_bindings) == 0 && output.workload_identity_members["sa-ml-runner"] == null
    error_message = "GKE Workload Identity bindings must be skipped when gke_hub_project_id is empty"
  }

  assert {
    condition     = length(google_storage_bucket.buckets) == 0 && length(output.buckets) == 0
    error_message = "No storage buckets should be planned when storage_buckets is empty (module default)"
  }
}

# --- Input Validation Tests: Reject Invalid Configurations ---

run "verify_duplicate_account_id_validation" {
  command = plan

  variables {
    service_accounts = [
      { account_id = "sa-dup" },
      { account_id = "sa-dup" }
    ]
  }

  expect_failures = [
    var.service_accounts
  ]
}

run "verify_invalid_project_id_validation" {
  command = plan

  variables {
    project_id = "INVALID_PROJECT_ID!"
  }

  expect_failures = [
    var.project_id
  ]
}

run "reject_whitespace_default_location" {
  command = plan

  variables {
    default_location = "   "
  }

  expect_failures = [
    var.default_location
  ]
}

run "reject_invalid_root_labels" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    labels = {
      cost_center = "INVALID_UPPERCASE"
    }
  }

  expect_failures = [
    var.labels,
  ]
}

run "reject_invalid_bucket_name" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "Invalid_Bucket" = {
        name = "Invalid_Bucket"
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_valid_key_with_invalid_explicit_bucket_name" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        name = "goog-reserved-prefix-bucket"
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_duplicate_effective_bucket_names" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        name = "bkt-shared-collision"
      }
      "artifacts" = {
        name = "bkt-shared-collision"
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_invalid_per_bucket_labels" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        labels = {
          "Invalid_Key" = "UPPERCASE_VALUE"
        }
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_invalid_kms_key_name" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        kms_key_name = "invalid-kms-key-format"
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_retention_locked_without_retention_period" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        retention_period_days = null
        retention_is_locked   = true
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_invalid_storage_class" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        storage_class = "GLACIER"
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_non_positive_retention_period_days" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        retention_period_days = 0
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_invalid_lifecycle_action" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        lifecycle_rules = [
          {
            action = {
              type = "UnsupportedAction"
            }
            condition = {
              age = 30
            }
          }
        ]
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_set_storage_class_without_valid_target_class" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        lifecycle_rules = [
          {
            action = {
              type          = "SetStorageClass"
              storage_class = "INVALID_CLASS"
            }
            condition = {
              age = 30
            }
          }
        ]
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

run "reject_lifecycle_rule_with_empty_condition" {
  command = plan

  variables {
    project_id = "prj-ml-vision-test-dev"
    storage_buckets = {
      "raw-images" = {
        lifecycle_rules = [
          {
            action = {
              type = "Delete"
            }
            condition = {
              matches_prefix = []
            }
          }
        ]
      }
    }
  }

  expect_failures = [
    var.storage_buckets,
  ]
}

# --- Central MLflow Server Integration & Model Artifact Storage Tests ---

# Verify end-to-end MLflow bucket IAM bindings, Secret Manager resources, and outputs using default keys and SAs.
run "verify_mlflow_full_integration" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "https://mlflow.platform.agco.internal"
      }
    }
  }

  assert {
    condition     = google_storage_bucket_iam_member.central_mlflow_admin["central"].bucket == "prj-ml-vision-test-dev-artifacts" && google_storage_bucket_iam_member.central_mlflow_admin["central"].role == "roles/storage.objectAdmin" && google_storage_bucket_iam_member.central_mlflow_admin["central"].member == "serviceAccount:sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
    error_message = "Central MLflow SA must be granted roles/storage.objectAdmin on the tenant model artifacts bucket."
  }

  assert {
    condition     = google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"].bucket == "prj-ml-vision-test-dev-artifacts" && google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"].role == "roles/storage.objectAdmin" && google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"].member == "serviceAccount:sa-ml-runner@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "Tenant sa-ml-runner must be granted roles/storage.objectAdmin on the tenant model artifacts bucket."
  }

  assert {
    condition     = google_secret_manager_secret.mlflow_uri["central"].secret_id == "mlflow-tracking-uri" && google_secret_manager_secret.mlflow_uri["central"].project == "prj-ml-vision-test-dev" && length(google_secret_manager_secret.mlflow_uri["central"].replication[0].auto) == 1 && google_secret_manager_secret.mlflow_uri["central"].labels["cost_center"] == "ai-platform"
    error_message = "mlflow-tracking-uri secret must be created in the tenant project with automatic replication and module labels."
  }

  assert {
    condition     = nonsensitive(google_secret_manager_secret_version.mlflow_uri_version["central"].secret_data) == "https://mlflow.platform.agco.internal"
    error_message = "mlflow-tracking-uri secret version must store tracking_uri."
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.mlflow_uri_ml_runner_accessor["central"].secret_id == "mlflow-tracking-uri" && google_secret_manager_secret_iam_member.mlflow_uri_ml_runner_accessor["central"].role == "roles/secretmanager.secretAccessor" && google_secret_manager_secret_iam_member.mlflow_uri_ml_runner_accessor["central"].member == "serviceAccount:sa-ml-runner@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "sa-ml-runner must be granted roles/secretmanager.secretAccessor on mlflow-tracking-uri."
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["central"].secret_id == "mlflow-tracking-uri" && google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["central"].role == "roles/secretmanager.secretAccessor" && google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["central"].member == "serviceAccount:sa-shared-gke-accessor@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "sa-shared-gke-accessor must be granted roles/secretmanager.secretAccessor on mlflow-tracking-uri."
  }

  assert {
    condition     = output.mlflow_artifact_roots["central"] == "gs://prj-ml-vision-test-dev-artifacts/" && output.mlflow_secret_ids["central"] == "projects/prj-ml-vision-test-dev/secrets/mlflow-tracking-uri" && output.mlflow_artifact_root == "gs://prj-ml-vision-test-dev-artifacts/" && output.mlflow_secret_id == "projects/prj-ml-vision-test-dev/secrets/mlflow-tracking-uri"
    error_message = "Outputs mlflow_artifact_roots, mlflow_secret_ids, mlflow_artifact_root, and mlflow_secret_id must resolve accurately when MLflow integration is configured."
  }
}

# Verify custom bucket key, custom secret ID, custom service account IDs, and per-integration label merging.
run "verify_mlflow_custom_keys_sas_and_labels" {
  command = plan

  variables {
    storage_buckets = {
      "model-weights" = {
        storage_class      = "STANDARD"
        versioning_enabled = true
      }
    }
    service_accounts = [
      {
        account_id = "sa-custom-accessor"
      },
      {
        account_id = "sa-custom-runner"
      }
    ]
    mlflow_integrations = {
      "custom" = {
        central_sa_email               = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri                   = "https://mlflow.platform.agco.internal:5000/tracking"
        artifacts_bucket_key           = "model-weights"
        secret_id                      = "custom-mlflow-tracking-uri"
        ml_runner_sa_account_id        = "sa-custom-runner"
        cluster_accessor_sa_account_id = "sa-custom-accessor"
        labels = {
          component = "mlflow"
        }
      }
    }
  }

  assert {
    condition     = google_storage_bucket_iam_member.central_mlflow_admin["custom"].bucket == "prj-ml-vision-test-dev-model-weights" && google_storage_bucket_iam_member.ml_runner_artifacts_admin["custom"].bucket == "prj-ml-vision-test-dev-model-weights" && google_storage_bucket_iam_member.ml_runner_artifacts_admin["custom"].member == "serviceAccount:sa-custom-runner@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "Custom artifacts_bucket_key and ml_runner_sa_account_id must resolve target bucket and runner SA principal."
  }

  assert {
    condition     = google_secret_manager_secret.mlflow_uri["custom"].secret_id == "custom-mlflow-tracking-uri" && google_secret_manager_secret.mlflow_uri["custom"].labels["component"] == "mlflow" && google_secret_manager_secret.mlflow_uri["custom"].labels["cost_center"] == "ai-platform"
    error_message = "Custom secret_id and merged per-integration labels must be applied to google_secret_manager_secret.mlflow_uri."
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.mlflow_uri_ml_runner_accessor["custom"].member == "serviceAccount:sa-custom-runner@prj-ml-vision-test-dev.iam.gserviceaccount.com" && google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["custom"].member == "serviceAccount:sa-custom-accessor@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "Custom ml_runner_sa_account_id and cluster_accessor_sa_account_id must be granted secretAccessor on the custom secret."
  }

  assert {
    condition     = output.mlflow_artifact_roots["custom"] == "gs://prj-ml-vision-test-dev-model-weights/" && output.mlflow_secret_ids["custom"] == "projects/prj-ml-vision-test-dev/secrets/custom-mlflow-tracking-uri" && output.mlflow_artifact_root == "gs://prj-ml-vision-test-dev-model-weights/" && output.mlflow_secret_id == "projects/prj-ml-vision-test-dev/secrets/custom-mlflow-tracking-uri"
    error_message = "Outputs must reflect custom bucket and custom secret_id."
  }
}

# Verify explicit artifacts_bucket_name override (when storage_buckets is empty) and fallback to sa-cluster-accessor.
run "verify_mlflow_bucket_name_override_and_cluster_accessor_fallback" {
  command = plan

  variables {
    storage_buckets = {}
    service_accounts = [
      {
        account_id = "sa-cluster-accessor"
      },
      {
        account_id = "sa-ml-runner"
      }
    ]
    mlflow_integrations = {
      "central" = {
        central_sa_email      = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri          = "https://mlflow.platform.agco.internal:5000/tracking"
        artifacts_bucket_name = "prj-ml-vision-test-dev-model-artifacts"
      }
    }
  }

  assert {
    condition     = google_storage_bucket_iam_member.central_mlflow_admin["central"].bucket == "prj-ml-vision-test-dev-model-artifacts" && google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"].bucket == "prj-ml-vision-test-dev-model-artifacts" && output.mlflow_artifact_root == "gs://prj-ml-vision-test-dev-model-artifacts/"
    error_message = "Explicit artifacts_bucket_name override must be used for bucket IAM bindings and mlflow_artifact_root output."
  }

  assert {
    condition     = google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["central"].member == "serviceAccount:sa-cluster-accessor@prj-ml-vision-test-dev.iam.gserviceaccount.com"
    error_message = "Cluster accessor secret IAM binding must support sa-cluster-accessor when sa-shared-gke-accessor is not present."
  }
}

# Precondition failure tests: ensure missing buckets or missing service accounts fail at plan time.
run "reject_mlflow_missing_artifacts_bucket" {
  command = plan

  variables {
    storage_buckets = {}
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "https://mlflow.platform.agco.internal"
      }
    }
  }

  expect_failures = [
    google_storage_bucket_iam_member.central_mlflow_admin["central"],
    google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"],
  ]
}

run "reject_mlflow_missing_ml_runner_sa" {
  command = plan

  variables {
    service_accounts = [
      {
        account_id = "sa-shared-gke-accessor"
      }
    ]
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "https://mlflow.platform.agco.internal"
      }
    }
  }

  expect_failures = [
    google_storage_bucket_iam_member.ml_runner_artifacts_admin["central"],
    google_secret_manager_secret_iam_member.mlflow_uri_ml_runner_accessor["central"],
  ]
}

run "reject_mlflow_missing_cluster_accessor_sa" {
  command = plan

  variables {
    service_accounts = [
      {
        account_id = "sa-ml-runner"
      }
    ]
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "https://mlflow.platform.agco.internal"
      }
    }
  }

  expect_failures = [
    google_secret_manager_secret_iam_member.mlflow_uri_cluster_accessor["central"],
  ]
}

# Input validation failure tests: ensure malformed emails, non-HTTPS/invalid URLs, and invalid bucket/SA identifiers are rejected.
run "reject_invalid_central_mlflow_sa_email" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email = "not-a-gcp-service-account@example.com"
        tracking_uri     = "https://mlflow.platform.agco.internal"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}

run "reject_insecure_http_central_mlflow_tracking_uri" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "http://mlflow.platform.agco.internal"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}

run "reject_whitespace_or_invalid_port_in_mlflow_tracking_uri" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri     = "https://mlflow.platform.agco.internal:99999/invalid path"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}

run "reject_invalid_artifacts_bucket_name" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email      = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri          = "https://mlflow.platform.agco.internal"
        artifacts_bucket_name = "gs://invalid-prefix-bucket"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}

run "reject_invalid_artifacts_bucket_key" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email     = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri         = "https://mlflow.platform.agco.internal"
        artifacts_bucket_key = "INVALID_UPPERCASE_KEY"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}

run "reject_invalid_mlflow_sa_account_ids" {
  command = plan

  variables {
    mlflow_integrations = {
      "central" = {
        central_sa_email        = "sa-mlflow-central@prj-ai-platform-hub.iam.gserviceaccount.com"
        tracking_uri            = "https://mlflow.platform.agco.internal"
        ml_runner_sa_account_id = "bad"
      }
    }
  }

  expect_failures = [
    var.mlflow_integrations,
  ]
}
