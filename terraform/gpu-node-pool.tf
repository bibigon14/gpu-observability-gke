# GPU node pool: one L4 node (g2-standard-8) for vLLM.
#
# GKE handles the NVIDIA driver automatically starting with 1.30 - setting
# guest_accelerator.gpu_driver_installation_config.gpu_driver_version schedules
# the gke-gpu-driver installer DaemonSet on the node and the driver is ready
# before the device plugin advertises nvidia.com/gpu. No GPU Operator, no
# manual driver image pull - this is the whole config.
#
# GKE also adds the taint nvidia.com/gpu=present:NoSchedule automatically on
# GPU nodes (visible after apply via `kubectl describe node`), so vLLM pods
# need the matching toleration - set in manifests/vllm/deployment.yaml.

resource "google_container_node_pool" "gpu" {
  name     = "gpu"
  location = var.zone
  cluster  = google_container_cluster.main.name

  initial_node_count = var.gpu_node_count

  autoscaling {
    min_node_count = var.gpu_min_node_count
    max_node_count = var.gpu_max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type

    # Spot VMs are 60-80% cheaper and fine for a demo. Toggle off via the
    # gpu_spot variable if a capture run needs guaranteed-not-preempted.
    spot = var.gpu_spot

    # Larger root disk: vLLM image is ~8 GB and the model cache fills what
    # is left on a default 100 GB SSD. 150 GB gives headroom.
    disk_size_gb = 150
    disk_type    = "pd-balanced"

    guest_accelerator {
      type  = var.gpu_accelerator_type
      count = var.gpu_accelerator_count

      gpu_driver_installation_config {
        gpu_driver_version = var.gpu_driver_version
      }
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = {
      "workload-type" = "gpu"
    }

    # The nvidia.com/gpu NoSchedule taint is added by GKE automatically; no
    # need to declare it here. Declaring it duplicates and can confuse the
    # autoscaler.

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # Avoid replacing the whole pool on cosmetic label changes.
  lifecycle {
    ignore_changes = [
      node_config[0].labels,
    ]
  }
}
