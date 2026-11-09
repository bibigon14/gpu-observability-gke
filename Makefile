# Operational entrypoints for the demo lifecycle.
#
# `make up` brings up the whole stack (cluster + monitoring + workload) assuming
# bootstrap.md has been completed. `make down` destroys it. `make capture` is
# the manual port-forwards the money-shot screenshots are taken from.

.PHONY: help up apply manifests kubeconfig grafana destroy down status

help:
	@echo "targets:"
	@echo "  make up            - apply terraform + manifests (full demo bring-up)"
	@echo "  make apply         - terraform apply only"
	@echo "  make manifests     - kubectl apply -k manifests/ (workloads layer)"
	@echo "  make kubeconfig    - fetch cluster credentials into ~/.kube/config"
	@echo "  make grafana       - port-forward Grafana on localhost:3000"
	@echo "  make status        - cluster + node pools + vllm pod state"
	@echo "  make down          - terraform destroy (full teardown)"

up: apply kubeconfig manifests
	@echo "cluster + monitoring + vLLM up."
	@echo "run 'make grafana' to open http://localhost:3000"

apply:
	cd terraform && terraform apply

kubeconfig:
	gcloud container clusters get-credentials \
	  $$(terraform -chdir=terraform output -raw cluster_name) \
	  --zone=$$(terraform -chdir=terraform output -raw cluster_location) \
	  --project=$$(terraform -chdir=terraform output -raw project_id)

manifests:
	kubectl apply -k manifests/

grafana:
	@echo "Grafana admin password: see TF_VAR_grafana_admin_password"
	kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

status:
	@echo "== cluster =="
	@kubectl get nodes -o wide
	@echo
	@echo "== workload =="
	@kubectl -n workloads get pods -o wide
	@echo
	@echo "== gpu =="
	@kubectl get nodes -l workload-type=gpu -o jsonpath='{.items[*].status.allocatable}' | jq

destroy: down

down:
	cd terraform && terraform destroy
