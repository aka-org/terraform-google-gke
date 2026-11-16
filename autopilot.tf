resource "google_container_cluster" "autopilot" {
  count = var.mode == "autopilot" ? 1 : 0

  project  = var.project_id
  name     = var.name
  location = var.location

  enable_autopilot    = true
  deletion_protection = var.deletion_protection
  resource_labels     = var.labels

  network    = var.network
  subnetwork = var.subnetwork

  # VPC-native: pods and Services take addresses from the subnet's
  # secondary ranges.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = var.private_nodes
    enable_private_endpoint = false
  }

  # Always present, so an empty list closes the public IP endpoint
  # instead of leaving it open to every address.
  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = var.dns_endpoint_external
    }
  }

  release_channel {
    channel = var.release_channel
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.maintenance_start_time
    }
  }

  # The nodes Autopilot provisions run as the module's account.
  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
    }
  }

  depends_on = [google_project_iam_member.nodes]
}
