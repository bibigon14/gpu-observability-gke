# GPU observability stack on GKE.
#
# Unlike EKS (where we deploy nvidia-device-plugin ourselves against the
# accelerated AMI's host driver), GKE auto-installs BOTH the NVIDIA driver AND
# the device plugin via the gke-gpu-driver installer DaemonSet on any node
# whose node_config declares guest_accelerator with gpu_driver_version set.
# That is why gpu-node-pool.tf is the whole GPU setup here and why this file
# only ships DCGM exporter.
#
# Chart versions pinned from the first green run (helm list -A) so a clean
# rebuild is reproducible.

locals {
  gpu_tolerations = [{
    key      = "nvidia.com/gpu"
    operator = "Equal"
    value    = "present"
    effect   = "NoSchedule"
  }]
  gpu_node_selector = {
    "workload-type" = "gpu"
  }
}

resource "helm_release" "dcgm_exporter" {
  name             = "dcgm-exporter"
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = "4.8.4"
  namespace        = "gpu-stack"
  create_namespace = true
  timeout          = 300

  values = [yamlencode({
    nodeSelector = local.gpu_node_selector
    tolerations  = local.gpu_tolerations

    # Let kube-prometheus-stack discover it via ServiceMonitor. The chart
    # hard-codes scrapeTimeout=25s and Prometheus Operator rejects a timeout
    # longer than the scrape interval; overriding both keeps the defaults
    # consistent with the EKS mirror.
    serviceMonitor = {
      enabled     = true
      interval    = "30s"
      honorLabels = true
    }
  })]

  depends_on = [
    helm_release.kube_prometheus_stack,
    google_container_node_pool.gpu,
  ]
}
