# GKE cluster + default system node pool.
#
# Zonal cluster (one control plane) rather than regional because this is a
# short-lived demo that does not need the HA control plane's 2x cost. VPC-native
# mode, workload identity on, release channel managed - the GKE 2026 defaults.
#
# The system node pool is a small CPU pool for the kube-system add-ons that GKE
# runs, plus the kube-prometheus-stack we install in monitoring.tf. The GPU pool
# is a separate node pool (gpu-node-pool.tf) with taints so only vLLM lands on it.

resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.zone

  # The default node pool is created and immediately destroyed. We manage the
  # real node pools as separate google_container_node_pool resources, which
  # lets us change the system pool without recreating the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  # Only pin a specific version when the caller sets one; otherwise let the
  # release channel pick, which is the recommended path for GPU driver support.
  min_master_version = var.kubernetes_version == "" ? null : var.kubernetes_version

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.main.name

  # VPC-native (alias IPs). The secondary range names come from the subnet.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity: the recommended way to let pods authenticate to Google
  # APIs without JSON service-account keys. Even for a demo this is one line.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # GKE Dataplane V2 (eBPF, Cilium-based) rather than the legacy kube-proxy +
  # iptables datapath. Default on new clusters; opting in here makes the choice
  # explicit so readers do not assume iptables.
  datapath_provider = "ADVANCED_DATAPATH"

  # Delete-protection off because this is a demo cluster that will be torn down.
  deletion_protection = false
}

# --- System node pool ---------------------------------------------------------
#
# Small CPU pool for GKE add-ons, operators, and the kube-prometheus-stack
# server + Grafana. Two e2-standard-2 are enough; the GPU pool handles vLLM.

resource "google_container_node_pool" "system" {
  name     = "system"
  location = var.zone
  cluster  = google_container_cluster.main.name

  initial_node_count = 2

  autoscaling {
    min_node_count = 2
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Least-privilege scopes: the node service account can only reach what it
    # needs (storage read-only for image pulls, logging/monitoring write).
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      "workload-type" = "system"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
