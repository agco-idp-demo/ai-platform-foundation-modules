# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

provider "google" {
  project = var.project_id
  region  = var.region
}

module "ml_tenant" {
  source = "../../"

  project_id          = var.project_id
  gke_hub_project_id  = var.gke_hub_project_id
  apis                = var.apis
  service_accounts    = var.service_accounts
  default_location    = var.default_location
  labels              = var.labels
  storage_buckets     = var.storage_buckets
  mlflow_integrations = var.mlflow_integrations
}
