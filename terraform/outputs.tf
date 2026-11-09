output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "Cluster API endpoint. HTTPS, consumed by kubectl after `gcloud container clusters get-credentials`."
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "Cluster zone (zonal cluster)."
  value       = google_container_cluster.main.location
}

output "kubeconfig_command" {
  description = "Run this to update ~/.kube/config so kubectl points at the new cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --zone=${google_container_cluster.main.location} --project=${var.project_id}"
}

output "grafana_port_forward_command" {
  description = "Run this to open Grafana on http://localhost:3000 - user admin, password from TF_VAR_grafana_admin_password."
  value       = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80"
}
