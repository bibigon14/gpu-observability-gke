# Observability control plane: kube-prometheus-stack.
#
# The chart ships Prometheus Operator CRDs, Prometheus, Alertmanager, Grafana,
# node-exporter, kube-state-metrics and the standard set of ServiceMonitors.
# DCGM exporter (gpu-stack.tf) and vLLM (manifests/vllm/) attach to it via
# ServiceMonitor CRs with no extra wiring.
#
# Pinned to the chart version resolved on the first green run - `helm list -A
# -n monitoring` shows the exact version if the chart ever needs an upgrade.

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "75.18.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600

  values = [yamlencode({
    # Keep the kube-prometheus-stack footprint off the GPU node.
    prometheus = {
      prometheusSpec = {
        # Pick up ServiceMonitors from any namespace without a label selector -
        # dcgm-exporter and vllm live in their own namespaces.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false

        nodeSelector = {
          "workload-type" = "system"
        }

        retention = "7d"
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        nodeSelector = {
          "workload-type" = "system"
        }
      }
    }

    grafana = {
      adminPassword = var.grafana_admin_password
      nodeSelector = {
        "workload-type" = "system"
      }
      service = {
        type = "ClusterIP"
      }
    }

    # These stay on system nodes.
    nodeExporter     = { enabled = true }
    kubeStateMetrics = { enabled = true }
  })]

  depends_on = [
    google_container_node_pool.system,
  ]
}
