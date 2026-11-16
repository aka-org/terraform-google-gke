# The account every node runs as, in both modes, with only what a node
# needs. Workloads don't use it: each gets its own Google identity
# through Workload Identity.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = var.node_service_account_id
  display_name = "Nodes of the ${var.name} GKE cluster"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(var.node_service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

locals {
  cluster = var.mode == "autopilot" ? google_container_cluster.autopilot[0] : google_container_cluster.standard[0]
}
