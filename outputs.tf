output "name" {
  description = "The name of the cluster"
  value       = local.cluster.name
}

output "id" {
  description = "The cluster's id (projects/<project>/locations/<location>/clusters/<name>)"
  value       = local.cluster.id
}

output "location" {
  description = "The region or zone of the cluster"
  value       = local.cluster.location
}

output "mode" {
  description = "autopilot or standard"
  value       = var.mode
}

output "endpoint" {
  description = "The IP address of the control plane's public endpoint"
  value       = local.cluster.endpoint
}

output "dns_endpoint" {
  description = "The control plane's DNS endpoint, where access is decided by IAM"
  value       = try(local.cluster.control_plane_endpoints_config[0].dns_endpoint_config[0].endpoint, null)
}

output "ca_certificate" {
  description = "The cluster's public CA certificate, base64-encoded (for clients using the IP endpoint)"
  value       = try(local.cluster.master_auth[0].cluster_ca_certificate, null)
}

output "workload_pool" {
  description = "The Workload Identity pool pods' identities belong to (<project>.svc.id.goog)"
  value       = "${var.project_id}.svc.id.goog"
}

output "node_service_account_email" {
  description = "Email of the service account the nodes run as"
  value       = google_service_account.nodes.email
}
