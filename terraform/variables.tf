variable "project_id" {
  description = "GCP project ID. Set via TF_VAR_project_id or terraform.tfvars."
  type        = string
}

variable "region" {
  description = "GCP region. us-west1 chosen because that is where the NVIDIA_L4_GPUS quota lives."
  type        = string
  default     = "us-west1"
}

variable "zone" {
  description = "GCP zone for the zonal cluster. Zonal is cheap for a demo; regional adds 2 extra control-plane replicas and 2x cost for no portfolio value."
  type        = string
  default     = "us-west1-a"
}

variable "cluster_name" {
  description = "GKE cluster name."
  type        = string
  default     = "gpu-observability-demo"
}

variable "kubernetes_version" {
  description = "GKE control plane version. Empty string means use the release channel's default, which is the recommended path for GPU drivers (GKE 1.30+ auto-installs them)."
  type        = string
  default     = ""
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, STABLE. REGULAR tracks the general release cadence and is the right default for a demo."
  type        = string
  default     = "REGULAR"
}

# --- GPU node pool ------------------------------------------------------------

variable "gpu_machine_type" {
  description = "GPU instance type. g2-standard-8 = 1x NVIDIA L4 (24GB), 8 vCPU, 32GB RAM."
  type        = string
  default     = "g2-standard-8"
}

variable "gpu_accelerator_type" {
  description = "NVIDIA accelerator type. nvidia-l4 is the Ada Lovelace generation (24GB VRAM) and the modern replacement for T4."
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_accelerator_count" {
  description = "GPUs per node. g2-standard-8 is a 1-GPU shape."
  type        = number
  default     = 1
}

variable "gpu_node_count" {
  description = "Initial GPU node count. 1 is enough for the whole demo; destroy when done."
  type        = number
  default     = 1
}

variable "gpu_min_node_count" {
  description = "Minimum GPU nodes when autoscaling. 0 lets the pool scale to zero when idle - but note GKE still charges for the instance until the autoscaler collects it (~10 min)."
  type        = number
  default     = 0
}

variable "gpu_max_node_count" {
  description = "Maximum GPU nodes when autoscaling. Keep small - this project is about one GPU, not a fleet."
  type        = number
  default     = 2
}

variable "gpu_spot" {
  description = "Use Spot VMs (~60-80% discount) for the GPU node pool. True by default; set false if a demo capture needs guaranteed availability."
  type        = bool
  default     = true
}

variable "gpu_driver_version" {
  description = "Driver version managed by GKE: DEFAULT (recommended) or LATEST. GKE 1.30+ auto-installs the NVIDIA driver via the gke-gpu-operator daemon on nodes with this annotation set."
  type        = string
  default     = "DEFAULT"
}

# --- Monitoring ---------------------------------------------------------------

variable "grafana_admin_password" {
  description = "Grafana admin password for kube-prometheus-stack. Set via TF_VAR_grafana_admin_password - never commit it."
  type        = string
  sensitive   = true
}
