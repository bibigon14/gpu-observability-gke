# GPU Observability on GKE

Reliability and cost observability for GPU workloads on Google Kubernetes
Engine. A real, applyable cluster that provisions an L4 node pool on GKE's
managed GPU runtime, runs **DCGM exporter** against the GKE-installed driver,
and surfaces the gap that drives GPU cost: **allocated GPU vs working GPU**.

Built to be stood up, demonstrated, and destroyed the same day. Single
`g2-standard-8` (one NVIDIA L4, 24 GB), so a full apply/demo/destroy cycle
costs a few dollars.

> Companion to [gpu-observability-eks](https://github.com/bibigon14/gpu-observability-eks).
> Same observability story (DCGM metrics, vLLM, kube-prometheus-stack, SLO
> burn-rate alerts, cost dashboards) on a different cloud and a newer GPU
> generation. Side-by-side the two repos show which parts of the design are
> cloud-portable and which pieces (driver install, node pool shape, device
> plugin) are not.

## Why this exists

GPUs are the most expensive compute in a cluster, and the default scheduler
view of them is binary and misleading:

- A pod requests `nvidia.com/gpu: 1` and holds a **whole** card. There is no
  "millicore" equivalent - allocation is all-or-nothing unless you configure
  time-slicing or MIG.
- `nvidia-smi` / `DCGM_FI_DEV_GPU_UTIL` reports "utilization" that only means
  _a kernel was running_. A tiny kernel on one SM shows 100%. A card can look
  saturated and be almost idle.

So the expensive failure mode is a GPU that is **allocated but idle**: memory
reserved, a workload resident, engines doing nothing. On a fleet of A100s or
H100s that gap is burned money. This project makes it visible and alerts on
it.

## The gap, on a live L4

Both captured from the shipped Grafana dashboard against a real `g2-standard-8`
(one NVIDIA L4, 24 GB), with vLLM serving `facebook/opt-1.3b`.

**Allocated but idle** - vLLM resident in 19.6 GB of framebuffer (the full
`gpu_memory_utilization=0.9` reservation for weights plus KV cache), every
engine flat at zero. One whole L4 held hostage: the exact state the
`GPUAllocatedButIdle` alert fires on.

![GPU allocated but idle](docs/screenshots/01-idle.png)

**Under load** - the same card driven by 20 concurrent inference streams.
Framebuffer did not change (same KV cache), but **`GPU utilization` climbed
to 87%**, **power draw jumped from 38 W to 70.5 W** (near the L4's 72 W TDP),
and **vLLM pushed ~1000 generation tokens/sec**. The point of the two shots
side by side: "allocation" tells you nothing about "work" - `FB_USED` barely
moves between the two states, but every real signal (power, temperature,
throughput, engine activity) swings by an order of magnitude. That gap is
what a GPU observability stack has to make legible.

![GPU under load](docs/screenshots/02-under-load.png)

| metric                   | idle    | under load | delta       |
|--------------------------|---------|------------|-------------|
| `DCGM_FI_DEV_FB_USED`    | 19.6 GB | 19.6 GB    | unchanged   |
| `DCGM_FI_DEV_GPU_UTIL`   | 0%      | 87%        | +87pp       |
| `DCGM_FI_DEV_POWER_USAGE`| 38 W    | 70.5 W     | +32 W (near TDP) |
| `DCGM_FI_DEV_GPU_TEMP`   | 65 C    | 77 C       | +12 C       |
| `vllm:generation_tokens_total` rate | 0 tok/s | ~1000 tok/s | +1000 tok/s |
| `vllm:num_requests_running`         | 0       | ~20         | +20         |

## Architecture

GKE in `us-west1`, zonal (one control plane, cheap for a demo), two node
pools:

```mermaid
flowchart TB
  subgraph GPU["GPU node pool - g2-standard-8, NVIDIA L4, taint nvidia.com/gpu=present"]
    direction LR
    DRIVER["gke-gpu-driver installer<br/>(GKE DaemonSet, auto-managed)"]
    DP["GKE device plugin<br/>advertises nvidia.com/gpu<br/>(no helm chart, GKE ships it)"]
    DCGM["dcgm-exporter<br/>:9400 /metrics"]
    VLLM["vLLM<br/>facebook/opt-1.3b<br/>:8000"]
  end

  subgraph SYSTEM["System node pool - e2-standard-2 x 2"]
    direction LR
    PROM["Prometheus<br/>+ Alertmanager<br/>+ Grafana"]
    KSM["kube-state-metrics"]
  end

  DCGM -->|ServiceMonitor| PROM
  VLLM -->|ServiceMonitor| PROM
  PROM -->|burn-rate alerts| ALERT((Alertmanager))
```

Two layers of alerting riding on the DCGM and vLLM metrics (will ship with
v0.2 and v0.3 - see roadmap below): one reliability layer (`VLLMHighTTFT`,
`VLLMQueueBackup`, `GPUAllocatedButIdle`), one SLO layer (multi-window
multi-burn-rate on `p99 TTFT < 1s` straight from the Google SRE Workbook
chapter 5).

## What's different from the EKS mirror

The observability story is identical. The host story is not:

| Aspect             | EKS (companion repo)                                 | GKE (this repo)                                                                 |
|--------------------|------------------------------------------------------|---------------------------------------------------------------------------------|
| GPU driver         | Pre-baked in the AL2023 accelerated AMI              | Installed by GKE's `gke-gpu-driver` DaemonSet on demand                         |
| Device plugin      | We ship `nvidia-device-plugin` Helm chart            | GKE ships it automatically with the driver                                      |
| Node taint         | Declared in Terraform (`nvidia.com/gpu=true`)        | Added by GKE automatically (`nvidia.com/gpu=present`)                           |
| DCGM exporter      | Helm chart, same version                             | Helm chart, same version                                                        |
| vLLM manifests     | Same `facebook/opt-1.3b` image, same ServiceMonitor  | Same, modulo the toleration value (`true` -> `present`)                         |
| Cluster networking | AWS VPC CNI                                          | GKE Dataplane V2 (eBPF, Cilium-based)                                           |

The Terraform code for the GKE side is **shorter** than the EKS side because
of these managed pieces. That is itself a portfolio point: picking the cloud
on the strength of its managed GPU story is a real trade-off and worth being
able to speak to.

## Deploy

See [`bootstrap.md`](bootstrap.md) for the one-time GCS state bucket and GPU
quota setup. Then:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: project_id, grafana_admin_password

terraform init
terraform apply
```

Roughly:

1. VPC + subnet (secondary ranges for Pods and Services)
2. GKE cluster (zonal, release channel REGULAR, Dataplane V2)
3. System node pool (e2-standard-2 x 2) for kube-prometheus-stack
4. GPU node pool (g2-standard-8, 1x L4, Spot by default, 150 GB pd-balanced)
5. kube-prometheus-stack helm release
6. DCGM exporter helm release (depends_on the GPU pool existing)

End-to-end ~12 minutes.

When done:

```bash
terraform destroy
```

The GPU pool is Spot by default (~60-80% cheaper); flip
`gpu_spot = false` if a specific demo capture needs guaranteed-not-preempted.

## Status

**v0.1** shipped 2026-11-08. Terraform brings up the cluster, both node
pools, kube-prometheus-stack; raw DaemonSet manifests ship DCGM exporter
and vLLM. Captured the money-shot pair (idle / under load) on a real L4
Spot in us-west1-a with ~1000 tok/s under 20 concurrent streams. Full
apply/demo/destroy cycle cost under $2.

**Known GKE-vs-EKS gotchas documented in code comments:**
- NVIDIA DCGM Helm chart hard-codes a securityContext that conflicts with
  GKE COS's CDI runtime; this project ships DCGM as a raw DaemonSet with
  the escape hatches (`privileged: true`, hostPath on `/home/kubernetes/bin/nvidia`,
  LD_LIBRARY_PATH to the mounted libs) rather than vendoring the chart.
- GKE auto-applies a ResourceQuota that blocks the system-node-critical
  PriorityClass outside kube-system; cleared it in the DaemonSet spec.
- DCGM profiling fields (DCP) fail to initialize on Spot L4 without
  persistence mode; a custom counters.csv keeps only the regular NVML
  fields that work. The tensor-active vs gpu-util gap panel from the EKS
  mirror is deferred to a non-Spot run.
- GKE Cluster Autoscaler marks a GPU node with min=0 as DeletionCandidate
  within ~10 min if no pod schedules; pinned min_node_count=1 for demos.

**Up next** (mirroring the EKS repo's shipped v0.2 - v0.5):

- vLLM Deployment + Service + ServiceMonitor (`manifests/vllm/`); capture the
  allocated-but-idle and under-load screenshots on L4 for the README.
- Reliability alerts: `GPUAllocatedButIdle`, `VLLMHighTTFT`,
  `VLLMQueueBackup`, `VLLMKVCacheSaturated`, `VLLMSwappingUnderLoad`.
- SLO + cost dashboards: multi-window multi-burn-rate on `p99 TTFT < 1s`,
  cost records against the L4 on-demand hourly rate, `$/million tokens`
  headline figure.
- KEDA ScaledObject + a small chaos CronJob mirroring the EKS v0.5 demo:
  kill a vLLM pod every 5 minutes under load and watch the burn-rate alerts
  trip.

## License

[Apache 2.0](LICENSE).
