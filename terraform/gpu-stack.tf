# GPU observability stack on GKE: DCGM exporter.
#
# This file used to deploy the NVIDIA dcgm-exporter Helm chart. The chart
# hard-codes a securityContext with allowPrivilegeEscalation:false and
# capabilities.drop:[ALL]; GKE COS with the auto-installed driver uses CDI
# (not NVIDIA_VISIBLE_DEVICES), so the DCGM pod cannot see /dev/nvidia*
# without privileged:true, and Kubernetes itself rejects the combination:
#
#   cannot set `allowPrivilegeEscalation` to false and `privileged` to true
#
# The chart does not expose a knob to drop its hard-coded capabilities. Rather
# than vendor it, DCGM exporter now lives as a raw DaemonSet under
# manifests/dcgm/, applied by `kubectl apply -k manifests/` after the cluster
# comes up. Shorter spec, full control over securityContext and host mounts,
# no helm quirks.
