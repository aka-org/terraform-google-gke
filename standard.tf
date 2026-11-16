resource "google_container_cluster" "standard" {
  count = var.mode == "standard" ? 1 : 0

  project  = var.project_id
  name     = var.name
  location = var.location

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

  # Pods authenticate to Google as their own service accounts.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # GKE can't create a cluster without a node pool: this one exists only
  # until the cluster is up, then is removed in favour of node_pools.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  lifecycle {
    # Describes the removed default pool only; GKE reports its own values
    # back for it.
    ignore_changes = [node_config]
  }

  depends_on = [google_project_iam_member.nodes]
}

resource "google_container_node_pool" "pools" {
  for_each = var.mode == "standard" ? { for p in var.node_pools : p.name => p } : {}

  project        = var.project_id
  name           = each.value.name
  cluster        = google_container_cluster.standard[0].name
  location       = var.location
  node_locations = each.value.node_locations

  initial_node_count = each.value.min_count

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = each.value.machine_type
    spot         = each.value.spot
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    labels       = each.value.labels

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Pods reach the metadata server through GKE's, which hands out their
    # Workload Identity instead of the node's account.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    dynamic "taint" {
      for_each = each.value.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }

  lifecycle {
    # The autoscaler owns the node count after creation.
    ignore_changes = [initial_node_count]
  }
}
