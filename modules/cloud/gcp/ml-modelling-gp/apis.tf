# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

# Enable GCP Project Services safely using for_each over the apis map
resource "google_project_service" "services" {
  for_each = var.apis

  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = each.value.disable_on_destroy
  disable_dependent_services = each.value.disable_dependent_services
}
