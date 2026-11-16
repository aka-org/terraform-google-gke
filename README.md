# terraform-google-gke

Terraform module for a Google Kubernetes Engine cluster in one of two modes:

- **`autopilot`** (the default): Google provisions and runs the nodes; you pay for what the pods request.
- **`standard`**: you define node pools (machine type, Spot, autoscaling) and pay for the nodes.

Both modes share the same shape, so a workload with explicit resource requests and nothing privileged runs unchanged on either:

- **VPC-native**: pods and Services take addresses from two secondary ranges of the nodes' subnet.
- **Private nodes** by default: no external addresses, so the subnet needs Cloud NAT for outbound internet access (pulling images from outside Google, calling external APIs).
- **Control plane closed by default**: its public IP endpoint admits only the ranges in `master_authorized_networks` (none by default); its DNS endpoint, opened with `dns_endpoint_external`, decides access by IAM instead of source address.
- **Workload Identity**: pods authenticate to Google as their own service accounts (`<project>.svc.id.goog`).
- **A dedicated node service account** with only what a node needs (logs, metrics, pulling from the project's Artifact Registry); the default Compute Engine account is never used.
- A release channel, a daily maintenance window and deletion protection.

## Usage

```hcl
module "gke" {
  source  = "aka-org/gke/google"
  version = "~> 0.1"

  project_id = "my-project"
  name       = "main"
  location   = "europe-west1"

  network             = module.network.network_self_link
  subnetwork          = module.network.subnetworks["nodes"].self_link
  pods_range_name     = "pods"
  services_range_name = "services"

  dns_endpoint_external = true
}
```

For a Standard cluster, set `mode = "standard"`, a zone or region as `location`, and `node_pools`. `examples/` has a complete configuration of each mode, network included.

Connect through the DNS endpoint with `gcloud container clusters get-credentials <name> --location <location> --dns-endpoint`; the caller needs `roles/container.developer` (or another role holding `container.clusters.connect`).

## Behaviour worth knowing

- **Changing `mode` replaces the cluster.** GKE can't convert a cluster between Autopilot and Standard: the old one is destroyed and a new one created, workloads and all.
- **`deletion_protection` is on by default.** To destroy the cluster, set it to `false`, apply, then destroy.
- **An empty `master_authorized_networks` closes the public IP endpoint**; it does not open it to everyone. With `dns_endpoint_external = false` as well, the control plane is reachable only from inside the VPC.
- **Nothing secret is stored in state.** The module issues no client certificate or password; `ca_certificate` is the cluster's public certificate.
- **The project needs the Kubernetes Engine and Compute Engine APIs** (`container.googleapis.com`, `compute.googleapis.com`) enabled before the module is applied.
- **Standard mode creates and then removes a one-node default pool**, which GKE requires to create a cluster; `node_pools` are the pools that stay.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Where the cluster runs: a region (europe-west1) for a regional cluster, which Autopilot requires, or a zone (europe-west1-b) for a zonal Standard cluster | `string` | n/a | yes |
| name | The name of the cluster | `string` | n/a | yes |
| network | Name or self link of the VPC network | `string` | n/a | yes |
| pods\_range\_name | Name of the subnet's secondary range pods take their addresses from | `string` | n/a | yes |
| project\_id | The id of the project the cluster is created in | `string` | n/a | yes |
| services\_range\_name | Name of the subnet's secondary range Services take their addresses from | `string` | n/a | yes |
| subnetwork | Name or self link of the subnet the nodes run in | `string` | n/a | yes |
| deletion\_protection | If true, Terraform refuses to destroy the cluster until this is set to false and applied | `bool` | `true` | no |
| dns\_endpoint\_external | If true, the control plane's DNS endpoint accepts requests from outside Google Cloud: access is then decided by IAM (container.clusters.connect) instead of by source address, which suits CI runners without fixed addresses | `bool` | `false` | no |
| labels | Labels to add to the cluster | `map(string)` | `{}` | no |
| maintenance\_start\_time | Start of the daily four-hour window GKE may run upgrades in, HH:MM in UTC | `string` | `"03:00"` | no |
| master\_authorized\_networks | Address ranges allowed to reach the control plane's public IP endpoint. Empty (the default) admits none: the endpoint then answers only inside the VPC, and outside access goes through the DNS endpoint (dns\_endpoint\_external) | <pre>list(object({<br/>    cidr_block   = string<br/>    display_name = optional(string)<br/>  }))</pre> | `[]` | no |
| mode | autopilot (Google runs the nodes; pods are billed by their requests) or standard (node pools from node\_pools). A cluster can't be converted: changing this replaces it | `string` | `"autopilot"` | no |
| node\_pools | Node pools of a standard cluster (ignored in autopilot mode, where Google provisions nodes) | <pre>list(object({<br/>    name         = string<br/>    machine_type = string<br/>    # Spot VMs cost less and can be reclaimed by Google at any time.<br/>    spot = optional(bool, false)<br/>    # Autoscaling bounds, per zone the pool runs in.<br/>    min_count = optional(number, 1)<br/>    max_count = optional(number, 1)<br/>    # Zones of a regional cluster the pool runs in; unset uses the<br/>    # cluster's own.<br/>    node_locations = optional(list(string))<br/>    disk_size_gb   = optional(number, 50)<br/>    disk_type      = optional(string, "pd-balanced")<br/>    labels         = optional(map(string), {})<br/>    # Keeps pods off the pool unless they tolerate the taint.<br/>    taints = optional(list(object({<br/>      key    = string<br/>      value  = string<br/>      effect = string<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| node\_service\_account\_id | The id of the service account the nodes run as, created by this module (the default Compute Engine service account is never used) | `string` | `"gke-nodes"` | no |
| node\_service\_account\_roles | Project roles granted to the nodes' service account: what a node needs to send logs and metrics, and to pull images from the project's Artifact Registry. Pods get their own access through Workload Identity, not through this account | `list(string)` | <pre>[<br/>  "roles/container.defaultNodeServiceAccount",<br/>  "roles/artifactregistry.reader"<br/>]</pre> | no |
| private\_nodes | If true, nodes get no external address (outbound internet access then needs Cloud NAT on the subnet) | `bool` | `true` | no |
| release\_channel | The channel GKE upgrades the cluster on: RAPID, REGULAR, STABLE or EXTENDED | `string` | `"REGULAR"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| ca\_certificate | The cluster's public CA certificate, base64-encoded (for clients using the IP endpoint) |
| dns\_endpoint | The control plane's DNS endpoint, where access is decided by IAM |
| endpoint | The IP address of the control plane's public endpoint |
| id | The cluster's id (projects/<project>/locations/<location>/clusters/<name>) |
| location | The region or zone of the cluster |
| mode | autopilot or standard |
| name | The name of the cluster |
| node\_service\_account\_email | Email of the service account the nodes run as |
| workload\_pool | The Workload Identity pool pods' identities belong to (<project>.svc.id.goog) |
<!-- END_TF_DOCS -->

## Development

What a machine needs to work on this module:

| Tool | Version | Used for |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.11.4 | `fmt`, `validate`, `test` |
| [TFLint](https://github.com/terraform-linters/tflint) | >= 0.50 | lint (`.tflint.hcl`) |
| [terraform-docs](https://terraform-docs.io/user-guide/installation/) | >= 0.25 | the README's Inputs and Outputs tables (`.terraform-docs.yml`) |
| git | any | |

Nothing here needs Google Cloud credentials: `validate` and `tflint` read only the configuration, and the tests (`tests/`) run the module against a mocked provider, creating nothing. Only the examples create real resources.

The checks CI runs (aka-org/gcp-infra's `terraform-module-ci.yml`, called from `.github/workflows/ci.yml`), from the repository root:

```sh
terraform fmt -check -recursive -diff
terraform init -backend=false && terraform validate && terraform test
tflint --init && tflint --recursive
terraform-docs --output-check .
```

After changing a variable or an output, run `terraform-docs .` to rewrite the README's tables.

CI validates and tests twice: on the lowest supported Google provider (6.11.0, read from `versions.tf`; the first with the control plane's DNS endpoint) and on the newest release the constraint allows. It runs on every pull request and once a week.

### Releasing

A release is a merge to `main` whose `CHANGELOG.md` starts with a new `## X.Y.Z` heading: `.github/workflows/release.yml` runs the checks again, pushes the annotated tag `vX.Y.Z` (the Terraform Registry publishes from it) and creates the GitHub release with that changelog section as its notes. Keep changes that aren't released yet under a `## Unreleased` heading above the newest version.
