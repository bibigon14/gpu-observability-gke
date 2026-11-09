# VPC + subnet for the GKE cluster. Minimal layout: one custom VPC with one
# subnet, secondary ranges for Pods and Services so GKE can run in VPC-native
# (alias IP) mode. VPC-native is required for Shared VPC and for several
# networking features and is the GKE default on new clusters anyway.

resource "google_compute_network" "main" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "${var.cluster_name}-subnet"
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.30.0.0/20"

  # Secondary ranges for Pods and Services - required for VPC-native clusters.
  # /14 for Pods gives ~256k addresses, plenty for a one-node demo and matches
  # the GKE default so the layout is immediately recognizable.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.32.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.36.0.0/20"
  }

  # Private Google Access lets nodes without external IPs reach Google APIs
  # (needed for pulling images from GCR / Artifact Registry).
  private_ip_google_access = true
}
