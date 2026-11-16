# Runs the module against a mocked Google provider: no credentials, no
# API calls, nothing created. Run with `terraform test` from the
# repository root.

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      email = "gke-nodes@example-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id          = "example-project"
  name                = "main"
  location            = "europe-west1"
  network             = "main"
  subnetwork          = "nodes"
  pods_range_name     = "pods"
  services_range_name = "services"
}

run "autopilot_by_default" {
  command = plan

  assert {
    condition     = length(google_container_cluster.autopilot) == 1 && length(google_container_cluster.standard) == 0
    error_message = "The default mode creates one Autopilot cluster and no Standard one."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].enable_autopilot == true
    error_message = "The Autopilot cluster has Autopilot enabled."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].private_cluster_config[0].enable_private_nodes == true
    error_message = "Nodes are private by default."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].deletion_protection == true
    error_message = "Deletion protection is on by default."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].release_channel[0].channel == "REGULAR"
    error_message = "The default release channel is REGULAR."
  }
  assert {
    condition = alltrue([
      google_container_cluster.autopilot[0].ip_allocation_policy[0].cluster_secondary_range_name == "pods",
      google_container_cluster.autopilot[0].ip_allocation_policy[0].services_secondary_range_name == "services",
    ])
    error_message = "Pods and Services use the secondary ranges given."
  }
}

run "control_plane_is_closed_by_default" {
  command = plan

  assert {
    condition     = length(google_container_cluster.autopilot[0].master_authorized_networks_config) == 1
    error_message = "The authorized-networks block is always set, so the IP endpoint is never open to every address."
  }
  assert {
    condition     = length(google_container_cluster.autopilot[0].master_authorized_networks_config[0].cidr_blocks) == 0
    error_message = "No address range is admitted unless given."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].master_authorized_networks_config[0].gcp_public_cidrs_access_enabled == false
    error_message = "Google Cloud's public addresses are not admitted."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].control_plane_endpoints_config[0].dns_endpoint_config[0].allow_external_traffic == false
    error_message = "The DNS endpoint is closed to outside traffic unless asked for."
  }
}

run "control_plane_access_as_given" {
  command = plan

  variables {
    master_authorized_networks = [{ cidr_block = "203.0.113.7/32", display_name = "office" }]
    dns_endpoint_external      = true
  }

  assert {
    condition     = [for b in google_container_cluster.autopilot[0].master_authorized_networks_config[0].cidr_blocks : b.cidr_block] == ["203.0.113.7/32"]
    error_message = "The given ranges are admitted to the IP endpoint."
  }
  assert {
    condition     = google_container_cluster.autopilot[0].control_plane_endpoints_config[0].dns_endpoint_config[0].allow_external_traffic == true
    error_message = "dns_endpoint_external opens the DNS endpoint."
  }
}

run "nodes_run_as_the_module_account" {
  command = plan

  assert {
    condition     = google_service_account.nodes.account_id == "gke-nodes"
    error_message = "The node service account has the default id."
  }
  assert {
    condition     = toset(keys(google_project_iam_member.nodes)) == toset(["roles/container.defaultNodeServiceAccount", "roles/artifactregistry.reader"])
    error_message = "The node account gets the node role and read access to the registry, nothing more."
  }
}

run "autopilot_ignores_node_pools" {
  command = plan

  variables {
    node_pools = [{ name = "default", machine_type = "e2-standard-2" }]
  }

  assert {
    condition     = length(google_container_node_pool.pools) == 0
    error_message = "Autopilot provisions its own nodes: node_pools creates nothing."
  }
}

run "standard_with_node_pools" {
  command = plan

  variables {
    mode     = "standard"
    location = "europe-west1-b"
    node_pools = [
      { name = "default", machine_type = "e2-standard-2" },
      {
        name         = "jobs"
        machine_type = "e2-standard-4"
        spot         = true
        min_count    = 0
        max_count    = 2
        taints       = [{ key = "workload", value = "jobs", effect = "NO_SCHEDULE" }]
      },
    ]
  }

  assert {
    condition     = length(google_container_cluster.standard) == 1 && length(google_container_cluster.autopilot) == 0
    error_message = "mode = \"standard\" creates one Standard cluster and no Autopilot one."
  }
  assert {
    condition     = google_container_cluster.standard[0].remove_default_node_pool == true
    error_message = "The cluster's built-in pool is removed in favour of node_pools."
  }
  assert {
    condition     = google_container_cluster.standard[0].workload_identity_config[0].workload_pool == "example-project.svc.id.goog"
    error_message = "Workload Identity uses the project's pool."
  }
  assert {
    condition     = toset(keys(google_container_node_pool.pools)) == toset(["default", "jobs"])
    error_message = "One node pool per entry."
  }
  assert {
    condition     = google_container_node_pool.pools["default"].node_config[0].spot == false && google_container_node_pool.pools["jobs"].node_config[0].spot == true
    error_message = "A pool uses Spot VMs only when asked."
  }
  assert {
    condition     = google_container_node_pool.pools["jobs"].autoscaling[0].min_node_count == 0 && google_container_node_pool.pools["jobs"].autoscaling[0].max_node_count == 2
    error_message = "A pool scales between its min_count and max_count."
  }
  assert {
    condition     = google_container_node_pool.pools["default"].node_config[0].workload_metadata_config[0].mode == "GKE_METADATA"
    error_message = "Pods get their own identity from the metadata server, not the node's."
  }
  assert {
    condition     = length(google_container_node_pool.pools["jobs"].node_config[0].taint) == 1
    error_message = "A pool carries its taints."
  }
}

run "outputs_of_either_mode" {
  variables {
    deletion_protection = false
  }

  assert {
    condition     = output.name == "main" && output.mode == "autopilot"
    error_message = "The outputs describe the cluster created."
  }
  assert {
    condition     = output.workload_pool == "example-project.svc.id.goog"
    error_message = "workload_pool is the project's Workload Identity pool."
  }
  assert {
    condition     = output.node_service_account_email == "gke-nodes@example-project.iam.gserviceaccount.com"
    error_message = "The node account's email is an output."
  }
}

run "mode_is_validated" {
  command = plan

  variables {
    mode = "serverless"
  }

  expect_failures = [var.mode]
}

run "release_channel_is_validated" {
  command = plan

  variables {
    release_channel = "LATEST"
  }

  expect_failures = [var.release_channel]
}

run "maintenance_time_is_validated" {
  command = plan

  variables {
    maintenance_start_time = "3am"
  }

  expect_failures = [var.maintenance_start_time]
}

run "node_pool_bounds_are_validated" {
  command = plan

  variables {
    mode       = "standard"
    node_pools = [{ name = "default", machine_type = "e2-standard-2", min_count = 3, max_count = 1 }]
  }

  expect_failures = [var.node_pools]
}
