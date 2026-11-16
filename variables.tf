variable "project_id" {
  description = "The id of the project the cluster is created in"
  type        = string
}

variable "name" {
  description = "The name of the cluster"
  type        = string
}

variable "location" {
  description = "Where the cluster runs: a region (europe-west1) for a regional cluster, which Autopilot requires, or a zone (europe-west1-b) for a zonal Standard cluster"
  type        = string
}

variable "mode" {
  description = "autopilot (Google runs the nodes; pods are billed by their requests) or standard (node pools from node_pools). A cluster can't be converted: changing this replaces it"
  type        = string
  default     = "autopilot"

  validation {
    condition     = contains(["autopilot", "standard"], var.mode)
    error_message = "mode must be \"autopilot\" or \"standard\"."
  }
}

variable "network" {
  description = "Name or self link of the VPC network"
  type        = string
}

variable "subnetwork" {
  description = "Name or self link of the subnet the nodes run in"
  type        = string
}

variable "pods_range_name" {
  description = "Name of the subnet's secondary range pods take their addresses from"
  type        = string
}

variable "services_range_name" {
  description = "Name of the subnet's secondary range Services take their addresses from"
  type        = string
}

variable "private_nodes" {
  description = "If true, nodes get no external address (outbound internet access then needs Cloud NAT on the subnet)"
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "Address ranges allowed to reach the control plane's public IP endpoint. Empty (the default) admits none: the endpoint then answers only inside the VPC, and outside access goes through the DNS endpoint (dns_endpoint_external)"
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "dns_endpoint_external" {
  description = "If true, the control plane's DNS endpoint accepts requests from outside Google Cloud: access is then decided by IAM (container.clusters.connect) instead of by source address, which suits CI runners without fixed addresses"
  type        = bool
  default     = false
}

variable "release_channel" {
  description = "The channel GKE upgrades the cluster on: RAPID, REGULAR, STABLE or EXTENDED"
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE", "EXTENDED"], var.release_channel)
    error_message = "release_channel must be RAPID, REGULAR, STABLE or EXTENDED."
  }
}

variable "maintenance_start_time" {
  description = "Start of the daily four-hour window GKE may run upgrades in, HH:MM in UTC"
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "maintenance_start_time must be HH:MM (24-hour, UTC)."
  }
}

variable "deletion_protection" {
  description = "If true, Terraform refuses to destroy the cluster until this is set to false and applied"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to add to the cluster"
  type        = map(string)
  default     = {}
}

variable "node_service_account_id" {
  description = "The id of the service account the nodes run as, created by this module (the default Compute Engine service account is never used)"
  type        = string
  default     = "gke-nodes"
}

variable "node_service_account_roles" {
  description = "Project roles granted to the nodes' service account: what a node needs to send logs and metrics, and to pull images from the project's Artifact Registry. Pods get their own access through Workload Identity, not through this account"
  type        = list(string)
  default = [
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ]
}

variable "node_pools" {
  description = "Node pools of a standard cluster (ignored in autopilot mode, where Google provisions nodes)"
  type = list(object({
    name         = string
    machine_type = string
    # Spot VMs cost less and can be reclaimed by Google at any time.
    spot = optional(bool, false)
    # Autoscaling bounds, per zone the pool runs in.
    min_count = optional(number, 1)
    max_count = optional(number, 1)
    # Zones of a regional cluster the pool runs in; unset uses the
    # cluster's own.
    node_locations = optional(list(string))
    disk_size_gb   = optional(number, 50)
    disk_type      = optional(string, "pd-balanced")
    labels         = optional(map(string), {})
    # Keeps pods off the pool unless they tolerate the taint.
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = []

  validation {
    condition     = alltrue([for p in var.node_pools : p.min_count <= p.max_count])
    error_message = "A node pool's min_count can't exceed its max_count."
  }
}
