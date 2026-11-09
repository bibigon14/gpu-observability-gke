# Bootstrap

One-time setup before the first `terraform apply`. If a GCS state bucket from
another terraform-* project already exists in this billing account, reuse it
and skip step 1.

## 1. GCS state bucket

```bash
PROJECT_ID=dstepanov-gke-platform
BUCKET=dstepanov-tfstate-gke
REGION=us-west1

# Create the bucket if it does not exist. Uniform bucket-level access + public
# access prevention + versioning are the defaults for a Terraform state bucket.
gcloud storage buckets create gs://${BUCKET} \
  --project="${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://${BUCKET} --versioning

# Lifecycle: expire noncurrent state versions after 90 days.
cat > /tmp/lifecycle.json <<'JSON'
{
  "lifecycle": {
    "rule": [
      { "action": { "type": "Delete" }, "condition": { "numNewerVersions": 10, "isLive": false } }
    ]
  }
}
JSON
gcloud storage buckets update gs://${BUCKET} --lifecycle-file=/tmp/lifecycle.json
```

The state object lives under `gs://${BUCKET}/gpu-observability-gke/default.tfstate`
so this project is isolated from any other state files in the same bucket.

## 2. Quota

This project needs:

- **Global**: `GPUS_ALL_REGIONS >= 1`
- **Regional (us-west1)**: `NVIDIA_L4_GPUS >= 1`

Check current values:

```bash
gcloud compute project-info describe --format=json \
  | jq '.quotas[] | select(.metric == "GPUS_ALL_REGIONS")'

gcloud compute regions describe us-west1 --format=json \
  | jq '.quotas[] | select(.metric == "NVIDIA_L4_GPUS")'
```

Request increases via the console (IAM & Admin -> Quotas). For a new project
without billing history, a 1-GPU request for a portfolio demo is usually
auto-approved in minutes; larger requests go to human review.

## 3. Apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id, grafana_admin_password

terraform init
terraform apply
```

After apply (~12 min for cluster + node pools + helm charts), point kubectl at
the new cluster with the command `terraform output kubeconfig_command` prints.
