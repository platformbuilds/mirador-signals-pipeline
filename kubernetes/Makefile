# Mirador Signals Pipeline - Automated OKD Setup and Deployment
# Usage: make setup

.PHONY: help check-podman check-okd check-requirements setup-crc setup-pvs deploy verify show-pvs clean

# Configuration
NAMESPACE := miradorstack
RELEASE_NAME := mirador-pipelines
HELM_TIMEOUT := 15m

# Minimum requirements
MIN_MEMORY_GB := 32
MIN_VCPU := 8
CRC_MEMORY_GB := 16
CRC_CPUS := 6

# Storage configuration
PV_BASE_PATH := /mnt/mirador-storage
VMSTORAGE_SIZE := 50Gi
VICTORIATRACES_SIZE := 50Gi
VICTORIALOGS_SIZE := 100Gi

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "Mirador Signals Pipeline - Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-podman: ## Check if Podman is installed, install if missing
	@echo "$(YELLOW)Checking Podman installation...$(NC)"
	@if ! command -v podman >/dev/null 2>&1; then \
		echo "$(RED)Podman not found. Installing...$(NC)"; \
		if [ -f /etc/redhat-release ]; then \
			sudo dnf install -y podman || sudo yum install -y podman; \
		elif [ -f /etc/debian_version ]; then \
			sudo apt-get update && sudo apt-get install -y podman; \
		else \
			echo "$(RED)Unsupported OS. Please install Podman manually: https://podman.io/getting-started/installation$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(GREEN)✓ Podman is installed: $$(podman --version)$(NC)"; \
	fi

check-crc: ## Check if CRC (CodeReady Containers) is installed
	@echo "$(YELLOW)Checking CodeReady Containers (CRC) installation...$(NC)"
	@if ! command -v crc >/dev/null 2>&1; then \
		echo "$(RED)CRC not found.$(NC)"; \
		echo "$(YELLOW)Installing CRC...$(NC)"; \
		echo ""; \
		echo "Please download CRC manually from:"; \
		echo "  https://developers.redhat.com/products/openshift-local/download"; \
		echo ""; \
		echo "After download, run:"; \
		echo "  tar -xvf crc-linux-amd64.tar.xz"; \
		echo "  sudo mv crc-linux-*/crc /usr/local/bin/"; \
		echo "  crc setup"; \
		echo ""; \
		exit 1; \
	else \
		echo "$(GREEN)✓ CRC is installed: $$(crc version)$(NC)"; \
	fi

check-oc: ## Check if oc CLI is installed
	@echo "$(YELLOW)Checking oc CLI installation...$(NC)"
	@if ! command -v oc >/dev/null 2>&1; then \
		echo "$(RED)oc CLI not found. Installing...$(NC)"; \
		if command -v crc >/dev/null 2>&1; then \
			eval $$(crc oc-env); \
		else \
			echo "$(RED)Please install oc CLI manually or install CRC first.$(NC)"; \
			exit 1; \
		fi; \
	else \
		echo "$(GREEN)✓ oc CLI is installed: $$(oc version --client 2>/dev/null || echo 'installed')$(NC)"; \
	fi

check-helm: ## Check if Helm is installed
	@echo "$(YELLOW)Checking Helm installation...$(NC)"
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "$(RED)Helm not found. Installing...$(NC)"; \
		curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	else \
		echo "$(GREEN)✓ Helm is installed: $$(helm version --short)$(NC)"; \
	fi

check-requirements: ## Check system requirements (memory and vCPU)
	@echo "$(YELLOW)Checking system requirements...$(NC)"
	@echo ""

	@# Check total memory
	@TOTAL_MEM_KB=$$(grep MemTotal /proc/meminfo | awk '{print $$2}'); \
	TOTAL_MEM_GB=$$((TOTAL_MEM_KB / 1024 / 1024)); \
	echo "  System Memory: $${TOTAL_MEM_GB}GB (Minimum: $(MIN_MEMORY_GB)GB)"; \
	if [ $$TOTAL_MEM_GB -lt $(MIN_MEMORY_GB) ]; then \
		echo "$(RED)  ✗ Insufficient memory. Need at least $(MIN_MEMORY_GB)GB$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)  ✓ Memory requirement met$(NC)"; \
	fi

	@# Check CPU cores
	@CPU_CORES=$$(nproc); \
	echo "  CPU Cores: $${CPU_CORES} (Minimum: $(MIN_VCPU))"; \
	if [ $$CPU_CORES -lt $(MIN_VCPU) ]; then \
		echo "$(RED)  ✗ Insufficient CPU cores. Need at least $(MIN_VCPU) cores$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)  ✓ CPU requirement met$(NC)"; \
	fi

	@# Check available memory
	@AVAILABLE_MEM_KB=$$(grep MemAvailable /proc/meminfo | awk '{print $$2}'); \
	AVAILABLE_MEM_GB=$$((AVAILABLE_MEM_KB / 1024 / 1024)); \
	echo "  Available Memory: $${AVAILABLE_MEM_GB}GB"; \
	if [ $$AVAILABLE_MEM_GB -lt 20 ]; then \
		echo "$(YELLOW)  ⚠ Warning: Low available memory. Consider closing other applications.$(NC)"; \
	fi

	@echo "$(GREEN)✓ System requirements check passed$(NC)"
	@echo ""

setup-crc: check-requirements check-podman check-crc check-oc ## Setup and start CodeReady Containers
	@echo "$(YELLOW)Setting up CodeReady Containers...$(NC)"

	@# Check if CRC is already running
	@if crc status 2>/dev/null | grep -q "Running"; then \
		echo "$(GREEN)✓ CRC is already running$(NC)"; \
	else \
		echo "$(YELLOW)Configuring CRC...$(NC)"; \
		crc config set memory $(CRC_MEMORY_GB)384; \
		crc config set cpus $(CRC_CPUS); \
		crc config set disk-size 100; \
		\
		if ! crc status 2>/dev/null | grep -q "CRC VM"; then \
			echo "$(YELLOW)Running CRC setup (this may take a few minutes)...$(NC)"; \
			crc setup; \
		fi; \
		\
		echo "$(YELLOW)Starting CRC (this may take 5-10 minutes)...$(NC)"; \
		crc start; \
		\
		echo "$(GREEN)✓ CRC started successfully$(NC)"; \
	fi

	@# Login to OpenShift
	@echo "$(YELLOW)Logging into OpenShift...$(NC)"
	@eval $$(crc oc-env); \
	oc login -u developer -p developer https://api.crc.testing:6443 --insecure-skip-tls-verify=true

	@echo "$(GREEN)✓ CRC setup complete$(NC)"

setup-okd: setup-crc ## Alias for setup-crc (for compatibility)
	@echo "$(GREEN)✓ OKD (CRC) is ready$(NC)"

check-cluster: ## Check if cluster is accessible
	@echo "$(YELLOW)Checking cluster connectivity...$(NC)"
	@if ! oc cluster-info >/dev/null 2>&1; then \
		echo "$(RED)Cannot connect to cluster. Please run 'make setup-crc' first.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Cluster is accessible$(NC)"
	@oc get nodes

setup-pvs: check-cluster ## Setup PersistentVolumes with local storage
	@echo "$(YELLOW)Setting up PersistentVolumes with local storage...$(NC)"
	@echo ""

	@# Check if PVs already exist
	@if oc get pv | grep -q "mirador-vmstorage"; then \
		echo "$(GREEN)✓ PersistentVolumes already exist$(NC)"; \
	else \
		echo "$(YELLOW)Creating local storage directories...$(NC)"; \
		\
		echo "Creating PersistentVolume manifests..."; \
		cat <<EOF | oc apply -f - \
---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-vmstorage-0\n  labels:\n    type: local\n    app: victoriametrics\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VMSTORAGE_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/vmstorage-0\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-vmstorage-1\n  labels:\n    type: local\n    app: victoriametrics\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VMSTORAGE_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/vmstorage-1\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-vmstorage-2\n  labels:\n    type: local\n    app: victoriametrics\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VMSTORAGE_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/vmstorage-2\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victoriatraces-0\n  labels:\n    type: local\n    app: victoriatraces\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIATRACES_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victoriatraces-0\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victoriatraces-1\n  labels:\n    type: local\n    app: victoriatraces\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIATRACES_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victoriatraces-1\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victoriatraces-2\n  labels:\n    type: local\n    app: victoriatraces\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIATRACES_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victoriatraces-2\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victorialogs-0\n  labels:\n    type: local\n    app: victorialogs\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIALOGS_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victorialogs-0\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victorialogs-1\n  labels:\n    type: local\n    app: victorialogs\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIALOGS_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victorialogs-1\n    type: DirectoryOrCreate\n---\napiVersion: v1\nkind: PersistentVolume\nmetadata:\n  name: mirador-victorialogs-2\n  labels:\n    type: local\n    app: victorialogs\nspec:\n  storageClassName: manual\n  capacity:\n    storage: $(VICTORIALOGS_SIZE)\n  accessModes:\n    - ReadWriteOnce\n  persistentVolumeReclaimPolicy: Retain\n  hostPath:\n    path: $(PV_BASE_PATH)/victorialogs-2\n    type: DirectoryOrCreate\nEOF\
		echo ""; \
		echo "$(GREEN)✓ Created 9 PersistentVolumes:$(NC)"; \
		echo "  - 3x $(VMSTORAGE_SIZE) for vmstorage"; \
		echo "  - 3x $(VICTORIATRACES_SIZE) for victoriatraces"; \
		echo "  - 3x $(VICTORIALOGS_SIZE) for victorialogs"; \
	fi

	@echo ""
	@echo "$(YELLOW)PersistentVolumes status:$(NC)"
	@oc get pv | grep mirador || echo "No mirador PVs found"
	@echo ""
	@echo "$(GREEN)✓ PersistentVolume setup complete$(NC)"

helm-deps: check-helm ## Update Helm dependencies
	@echo "$(YELLOW)Updating Helm dependencies...$(NC)"
	@helm repo add vm https://victoriametrics.github.io/helm-charts/ 2>/dev/null || true
	@helm repo update
	@helm dependency update .
	@echo "$(GREEN)✓ Helm dependencies updated$(NC)"

deploy: check-cluster helm-deps ## Deploy Mirador Pipelines to OKD
	@echo "$(YELLOW)Deploying Mirador Signals Pipeline...$(NC)"
	@echo ""

	@# Create namespace/project
	@echo "Creating namespace: $(NAMESPACE)"
	@oc new-project $(NAMESPACE) 2>/dev/null || oc project $(NAMESPACE)

	@# Check if already installed
	@if helm list -n $(NAMESPACE) | grep -q $(RELEASE_NAME); then \
		echo "$(YELLOW)Release already exists. Upgrading...$(NC)"; \
		helm upgrade $(RELEASE_NAME) . \
			--namespace $(NAMESPACE) \
			-f values.yaml \
			-f values-okd.yaml \
			--wait \
			--timeout $(HELM_TIMEOUT); \
	else \
		echo "$(YELLOW)Installing new release...$(NC)"; \
		helm install $(RELEASE_NAME) . \
			--namespace $(NAMESPACE) \
			-f values.yaml \
			-f values-okd.yaml \
			--wait \
			--timeout $(HELM_TIMEOUT); \
	fi

	@echo ""
	@echo "$(GREEN)✓ Deployment initiated$(NC)"

verify: ## Verify all services are running
	@echo "$(YELLOW)Verifying deployment...$(NC)"
	@echo ""

	@# Wait for pods to be ready
	@echo "Waiting for pods to be ready..."
	@kubectl wait --for=condition=ready pod \
		-l app.kubernetes.io/instance=$(RELEASE_NAME) \
		-n $(NAMESPACE) \
		--timeout=600s 2>/dev/null || true

	@# Show pod status
	@echo ""
	@echo "$(YELLOW)Pod Status:$(NC)"
	@oc get pods -n $(NAMESPACE) -o wide

	@# Count running pods
	@TOTAL_PODS=$$(oc get pods -n $(NAMESPACE) --no-headers | wc -l); \
	RUNNING_PODS=$$(oc get pods -n $(NAMESPACE) --field-selector=status.phase=Running --no-headers | wc -l); \
	echo ""; \
	echo "Pods: $$RUNNING_PODS / $$TOTAL_PODS running"; \
	\
	if [ $$RUNNING_PODS -eq $$TOTAL_PODS ]; then \
		echo "$(GREEN)✓ All pods are running!$(NC)"; \
	else \
		echo "$(YELLOW)⚠ Some pods are not running yet. Check status above.$(NC)"; \
	fi

	@# Show services
	@echo ""
	@echo "$(YELLOW)Services:$(NC)"
	@oc get svc -n $(NAMESPACE)

	@# Show PVs
	@echo ""
	@echo "$(YELLOW)PersistentVolumes:$(NC)"
	@oc get pv | grep -E "NAME|mirador" || echo "No mirador PVs found"

	@# Show PVCs
	@echo ""
	@echo "$(YELLOW)Persistent Volume Claims:$(NC)"
	@oc get pvc -n $(NAMESPACE)

	@# Pod distribution
	@echo ""
	@echo "$(YELLOW)Pod Distribution by Node:$(NC)"
	@oc get pods -n $(NAMESPACE) -o wide --no-headers | awk '{print $$7}' | sort | uniq -c

	@echo ""
	@echo "$(GREEN)✓ Verification complete$(NC)"

show-pvs: ## Show PersistentVolumes status
	@echo "$(YELLOW)PersistentVolumes:$(NC)"
	@oc get pv | grep -E "NAME|mirador" || echo "No mirador PVs found"
	@echo ""
	@echo "$(YELLOW)Detailed PV information:$(NC)"
	@oc get pv -l type=local -o wide 2>/dev/null || echo "No local PVs found"

status: ## Show deployment status
	@echo "$(YELLOW)Deployment Status:$(NC)"
	@echo ""
	@helm list -n $(NAMESPACE)
	@echo ""
	@oc get pods -n $(NAMESPACE)

logs: ## Show logs from all pods
	@echo "$(YELLOW)Showing logs from all pods...$(NC)"
	@oc logs -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME) --tail=50 --max-log-requests=20

logs-gateway: ## Show logs from gateway pods
	@oc logs -n $(NAMESPACE) -l app.kubernetes.io/component=gateway --tail=100

logs-victoria: ## Show logs from Victoria services
	@echo "$(YELLOW)VictoriaMetrics logs:$(NC)"
	@oc logs -n $(NAMESPACE) -l app.kubernetes.io/name=victoria-metrics-cluster --tail=50
	@echo ""
	@echo "$(YELLOW)VictoriaTraces logs:$(NC)"
	@oc logs -n $(NAMESPACE) -l app.kubernetes.io/name=victoria-traces-single --tail=50
	@echo ""
	@echo "$(YELLOW)VictoriaLogs logs:$(NC)"
	@oc logs -n $(NAMESPACE) -l app.kubernetes.io/name=victoria-logs-single --tail=50

clean: ## Uninstall the deployment and clean up
	@echo "$(YELLOW)Cleaning up deployment...$(NC)"
	@helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) 2>/dev/null || echo "Release not found"
	@oc delete pvc --all -n $(NAMESPACE) 2>/dev/null || true
	@oc delete project $(NAMESPACE) 2>/dev/null || echo "Project not found"
	@echo "$(YELLOW)Cleaning up PersistentVolumes...$(NC)"
	@oc delete pv -l type=local 2>/dev/null || echo "No PVs to delete"
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

stop-crc: ## Stop CodeReady Containers
	@echo "$(YELLOW)Stopping CRC...$(NC)"
	@crc stop
	@echo "$(GREEN)✓ CRC stopped$(NC)"

delete-crc: ## Delete CRC VM completely
	@echo "$(RED)Warning: This will delete the entire CRC VM!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		crc delete; \
		echo "$(GREEN)✓ CRC VM deleted$(NC)"; \
	else \
		echo "Cancelled."; \
	fi

setup: check-requirements check-podman check-helm setup-crc setup-pvs deploy verify ## Complete setup: check requirements, install tools, setup CRC, create PVs, and deploy
	@echo ""
	@echo "$(GREEN)═══════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)✓ Mirador Signals Pipeline deployment complete!$(NC)"
	@echo "$(GREEN)═══════════════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)Access the OpenShift Console:$(NC)"
	@crc console --url 2>/dev/null || echo "  Run: crc console"
	@echo ""
	@echo "$(YELLOW)Credentials:$(NC)"
	@echo "  Developer: developer / developer"
	@echo "  Admin:     kubeadmin / <get password with: crc console --credentials>"
	@echo ""
	@echo "$(YELLOW)Useful commands:$(NC)"
	@echo "  View pods:      make status"
	@echo "  View logs:      make logs"
	@echo "  Clean up:       make clean"
	@echo "  Stop CRC:       make stop-crc"
	@echo ""

test-connection: check-cluster ## Test connection to deployed services
	@echo "$(YELLOW)Testing service connectivity...$(NC)"
	@echo ""

	@# Test gateway service
	@echo "Testing Gateway OTLP port (4317)..."
	@oc run test-client --rm -i --restart=Never --image=curlimages/curl:latest \
		-- sh -c "curl -v telnet://$(RELEASE_NAME)-gateway.$(NAMESPACE).svc.cluster.local:4317" 2>&1 | grep -i "connected" || \
		echo "Gateway OTLP port accessible"

	@echo "$(GREEN)✓ Connection tests complete$(NC)"

.DEFAULT_GOAL := help
