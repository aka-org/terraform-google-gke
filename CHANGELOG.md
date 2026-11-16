# Changelog
All notable changes to this project will be documented in this file.

## Unreleased
### ADDED
- A GKE cluster in `autopilot` or `standard` mode: VPC-native on given secondary ranges, private nodes, a control plane closed to the internet except through authorized networks or its DNS endpoint, Workload Identity, a release channel, a daily maintenance window, deletion protection, and a dedicated service account for the nodes.
- `standard` mode: node pools with machine type, Spot, autoscaling bounds, labels and taints.
- Examples (`examples/autopilot`, `examples/standard`), tests (`tests/`) and CI.
