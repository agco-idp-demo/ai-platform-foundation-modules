# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0, < 7.0.0"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/ai-platform-infra:ml-modeling-tenant/v1.0.0"
  }
}
