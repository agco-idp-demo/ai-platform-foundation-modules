> Copyright 2026 Google. This software is provided as-is, without warranty or representation for any use or purpose. Your use of it is subject to your agreement with Google.

# Basic ML Modeling Tenant Module Example

This example demonstrates how to deploy the `ml-modeling-tenant` module via `.tfvars` to enable GCP APIs, provision Google Service Accounts (`sa-cluster-accessor`, `sa-ml-runner`), configure optional Workload Identity bindings for the central shared GKE cluster, and provision parameterized multi-bucket Cloud Storage (`raw-images`, `artifacts`, `telemetry`) with retention policies, lifecycle rules, and FinOps labels.

## Requirements

- **Terraform**: `>= 1.9.0`
- **Google Cloud Provider**: `>= 5.0.0, < 7.0.0`

## Usage

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Plan deployment:
   ```bash
   terraform plan -var-file="terraform.tfvars"
   ```

3. Apply configuration:
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_id` | Target GCP Project ID for the example | `string` | `"prj-t-demo-goldenpath-osxq"` | no |
| `region` | Target GCP Region for tenant resources | `string` | `"us-east4"` | no |
| `gke_hub_project_id` | Hub GCP Project ID for shared GKE cluster (leave empty to skip GKE Workload Identity bindings) | `string` | `""` | no |
| `apis` | Map of Google Cloud APIs to enable, keyed by service name | `map(object)` | `{}` | no |
| `service_accounts` | List of service accounts, KSA names, and IAM permissions | `list(object)` | `[]` | no |
| `default_location` | Default GCS location applied when a bucket does not specify a location | `string` | `"US"` | no |
| `labels` | Module-level GCP labels merged onto all provisioned storage buckets | `map(string)` | `{}` | no |
| `storage_buckets` | Map of GCS bucket configurations keyed by logical bucket identifier | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `project_id` | Target GCP project ID |
| `enabled_apis` | List of enabled APIs |
| `tenant_namespace` | Resolved Kubernetes namespace used for Workload Identity bindings |
| `service_accounts` | Map of created service accounts (`email`, `member`, `id`, `unique_id`, `ksa_name`, `workload_identity_member`), keyed by `account_id` |
| `workload_identity_members` | Map of Workload Identity member principal strings, keyed by `account_id` |
| `buckets` | Map of provisioned `google_storage_bucket` resources keyed by logical bucket key |
| `bucket_names` | Map of logical bucket keys to provisioned GCS bucket names |
| `bucket_urls` | Map of logical bucket keys to GCS bucket URLs (`gs://<bucket_name>`) |
| `bucket_self_links` | Map of logical bucket keys to GCS bucket self-links |

---

## License & Support

Copyright 2026 Google. This software is provided as-is, without warranty or representation for any use or purpose. Your use of it is subject to your agreement with Google.
