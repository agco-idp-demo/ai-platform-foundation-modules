# Copyright 2026 Google. This software is provided as-is, without warranty or
# representation for any use or purpose. Your use of it is subject to your
# agreement with Google.

locals {
  resolved_tenant_namespace = trimspace(var.tenant_namespace) != "" ? trimspace(var.tenant_namespace) : "workspace-${var.project_id}"

  # Normalise the list-of-objects into a map keyed by account_id, resolving ksa_name to account_id when empty.
  service_accounts_map = {
    for sa in var.service_accounts : sa.account_id => merge(sa, {
      ksa_name = coalesce(sa.ksa_name, sa.account_id)
    })
  }
}

# 1. Parameterized Service Accounts (via list-of-objects)
resource "google_service_account" "sas" {
  for_each = local.service_accounts_map

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name != "" ? each.value.display_name : null
  description  = each.value.description != "" ? each.value.description : null
}

# 2. Parameterized Project IAM Permissions for Service Accounts
locals {
  sa_permissions = flatten([
    for sa in var.service_accounts : [
      for role in sa.permissions : {
        key        = "${sa.account_id}-${role}"
        account_id = sa.account_id
        role       = role
      }
    ]
  ])

  sa_permissions_map = {
    for p in local.sa_permissions : p.key => p
  }
}

resource "google_project_iam_member" "sa_roles" {
  for_each = local.sa_permissions_map

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.sas[each.value.account_id].member

  depends_on = [
    google_service_account.sas,
    google_project_service.services
  ]
}

# 3. Dedicated Workload Identity Bindings for Tenant Service Accounts
locals {
  gke_hub_enabled = trimspace(var.gke_hub_project_id) != ""

  workload_identity_members = {
    for k, sa in local.service_accounts_map :
    k => local.gke_hub_enabled ? "serviceAccount:${trimspace(var.gke_hub_project_id)}.svc.id.goog[${local.resolved_tenant_namespace}/${sa.ksa_name}]" : null
  }
}

resource "google_service_account_iam_member" "workload_identity_bindings" {
  for_each = local.gke_hub_enabled ? local.service_accounts_map : {}

  service_account_id = google_service_account.sas[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_members[each.key]
}
