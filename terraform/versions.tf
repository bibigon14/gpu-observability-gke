terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  # Remote state in GCS. Reuses the bucket convention from terraform-gke-platform
  # (one bucket per billing account, one state object per project). See bootstrap.md.
  backend "gcs" {
    bucket = "dstepanov-tfstate-gke"
    prefix = "gpu-observability-gke"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = {
    project    = "gpu-observability-gke"
    managed_by = "terraform"
  }
}

# Kubernetes + Helm providers authenticate against the cluster created below. The
# google_client_config data source yields a short-lived OAuth2 token so this works
# locally and in CI without stashing a kubeconfig.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.main.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
