# A throwaway autopilot cluster in its own network: private nodes behind Cloud
# NAT, the control plane reachable through its DNS endpoint (IAM decides
# who may connect).
#
#   terraform init && terraform apply -var project_id=<project>
#   gcloud container clusters get-credentials example-autopilot --location europe-west1 --dns-endpoint --project <project>
#   terraform destroy -var project_id=<project>
#
# The project needs the Compute Engine and Kubernetes Engine APIs enabled.

terraform {
  required_version = ">= 1.11.4"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.11, < 8"
    }
  }
}

variable "project_id" {
  description = "The project the example is created in"
  type        = string
}

module "network" {
  source  = "aka-org/network/google"
  version = "0.2.0"

  project_id   = var.project_id
  network_name = "example-autopilot"

  subnetworks = [{
    name                     = "nodes"
    region                   = "europe-west1"
    ip_cidr_range            = "10.0.0.0/20"
    private_ip_google_access = true
    secondary_ip_ranges = [
      { range_name = "pods", ip_cidr_range = "10.4.0.0/14" },
      { range_name = "services", ip_cidr_range = "10.8.0.0/20" },
    ]
  }]

  nat_gateways = [{ name = "example-autopilot", region = "europe-west1" }]
}

module "gke" {
  source = "../.."

  project_id = var.project_id
  name       = "example-autopilot"
  location   = "europe-west1"
  mode       = "autopilot"

  network             = module.network.network_self_link
  subnetwork          = module.network.subnetworks["nodes"].self_link
  pods_range_name     = "pods"
  services_range_name = "services"

  dns_endpoint_external = true
  # A throwaway cluster: let `terraform destroy` remove it.
  deletion_protection = false
}

output "cluster" {
  description = "The cluster's name and DNS endpoint"
  value       = { name = module.gke.name, dns_endpoint = module.gke.dns_endpoint }
}
