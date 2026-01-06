# Quick Start Guide - Automated Setup

This guide covers automated setup using the Makefile for local development with CodeReady Containers (CRC).

## Prerequisites

- **RHEL/Fedora/CentOS** (or compatible Linux distribution)
- **Minimum System Requirements:**
  - 32GB RAM
  - 8 vCPUs
  - 100GB free disk space

## One-Command Setup

For a complete automated setup from scratch:

```bash
make setup
```

This single command will:
1. ✅ Check system requirements (memory, CPU)
2. ✅ Install Podman (if not present)
3. ✅ Install Helm (if not present)
4. ✅ Check/setup CodeReady Containers (CRC)
5. ✅ Start OKD local cluster
6. ✅ Create PersistentVolumes with local storage
7. ✅ Deploy Mirador Signals Pipeline
8. ✅ Verify all services are running

## Step-by-Step Setup

If you prefer to run each step individually:

### 1. Check Requirements

```bash
make check-requirements
```

Verifies your system has:
- Minimum 32GB RAM
- Minimum 8 CPU cores
- Sufficient available memory

### 2. Install Prerequisites

```bash
make check-podman  # Installs Podman if missing
make check-helm    # Installs Helm if missing
make check-crc     # Checks if CRC is installed
```

### 3. Setup CodeReady Containers

```bash
make setup-crc
```

This will:
- Configure CRC with 16GB memory and 6 CPUs
- Setup CRC (first time only)
- Start the OKD cluster
- Login to the cluster

### 4. Setup PersistentVolumes

```bash
make setup-pvs
```

Creates 9 PersistentVolumes with local storage:
- 3x 50Gi for VictoriaMetrics storage
- 3x 50Gi for VictoriaTraces storage
- 3x 100Gi for VictoriaLogs storage

### 5. Deploy the Pipeline

```bash
make deploy
```

Deploys all components:
- Gateway (3 replicas)
- Service Graph (1 replica)
- Span Metrics (1 replica)
- Isolation Forest (3 replicas)
- VictoriaMetrics cluster (9 pods)
- VictoriaTraces (3 replicas)
- VictoriaLogs (3 replicas)
- Adapters (4 pods)

### 6. Verify Deployment

```bash
make verify
```

Shows:
- Pod status and distribution
- Service endpoints
- PVC status
- Health checks

## Common Commands

### Monitoring

```bash
# Show deployment status
make status

# Show PersistentVolumes status
make show-pvs

# View logs from all pods
make logs

# View gateway logs
make logs-gateway

# View Victoria services logs
make logs-victoria
```

### Management

```bash
# Redeploy (upgrade)
make deploy

# Clean up deployment
make clean

# Stop CRC (keep VM)
make stop-crc

# Delete CRC completely
make delete-crc
```

### Troubleshooting

```bash
# Check cluster connectivity
make check-cluster

# Test service connections
make test-connection

# View detailed help
make help
```

## Access the Cluster

### OpenShift Web Console

```bash
crc console
```

**Credentials:**
- Developer: `developer` / `developer`
- Admin: `kubeadmin` / `<get with: crc console --credentials>`

### Command Line

```bash
# Already logged in after setup, but if needed:
eval $(crc oc-env)
oc login -u developer -p developer https://api.crc.testing:6443
```

## Verify Services

### Check All Pods

```bash
oc get pods -n miradorstack
```

Expected: 24 pods in Running state

### Check Services

```bash
oc get svc -n miradorstack
```

### Access VictoriaMetrics Query Interface

```bash
# Port-forward vmselect
oc port-forward -n miradorstack svc/mirador-pipelines-victoriametrics-victoria-metrics-cluster-vmselect 8481:8481

# Open in browser
http://localhost:8481/select/0/vmui
```

## Workflow Examples

### Fresh Installation

```bash
# Complete automated setup
make setup

# Access web console
crc console
```

### Daily Development

```bash
# Start CRC if stopped
make setup-crc

# Deploy latest changes
make deploy

# Check status
make status
```

### Cleanup and Restart

```bash
# Remove deployment
make clean

# Redeploy
make deploy
```

### Complete Cleanup

```bash
# Uninstall everything
make clean

# Stop CRC
make stop-crc

# Optional: Delete CRC VM completely
make delete-crc
```

## Resource Usage

### CRC Resource Allocation

The Makefile configures CRC with:
- **Memory:** 16GB (for CRC VM)
- **CPUs:** 6 cores
- **Disk:** 100GB

### Application Resource Requests

Total across all pods:
- **Memory:** ~32GB requested
- **CPU:** ~16 cores requested
- **Storage:** 600GB (PVCs)

### Storage Configuration

PersistentVolumes use local storage with the "manual" storage class:
- **Base Path:** `/mnt/mirador-storage`
- **VictoriaMetrics:** 3x 50Gi = 150Gi total
- **VictoriaTraces:** 3x 50Gi = 150Gi total
- **VictoriaLogs:** 3x 100Gi = 300Gi total
- **Total:** 600Gi across 9 PVs

To customize storage sizes, edit the Makefile variables:
```makefile
VMSTORAGE_SIZE := 50Gi
VICTORIATRACES_SIZE := 50Gi
VICTORIALOGS_SIZE := 100Gi
```

## Troubleshooting

### Issue: Insufficient Memory

```bash
# Check current allocation
free -h

# Increase CRC memory (requires restart)
crc config set memory 20480
crc stop
crc start
```

### Issue: Pods Pending

```bash
# Check pod events
oc describe pod <pod-name> -n miradorstack

# Check node resources
oc adm top nodes
```

### Issue: PVC Not Binding

```bash
# Check PersistentVolumes
make show-pvs

# Check PVC status
oc get pvc -n miradorstack
oc describe pvc <pvc-name> -n miradorstack

# Check if PVs exist
oc get pv | grep mirador

# If PVs don't exist, create them
make setup-pvs
```

### Issue: CRC Won't Start

```bash
# Check CRC status
crc status

# View logs
crc console --log

# Reset CRC (warning: deletes VM)
crc delete
make setup-crc
```

### Issue: Image Pull Errors

```bash
# Check image pull
oc describe pod <pod-name> -n miradorstack | grep -i image

# If needed, manually pull images
podman pull otel/opentelemetry-collector-contrib:latest
podman pull victoriametrics/victoria-metrics:latest
```

## Advanced Configuration

### Customize CRC Resources

Edit the Makefile variables:

```makefile
CRC_MEMORY_GB := 20    # Change from 16 to 20
CRC_CPUS := 8          # Change from 6 to 8
```

Then restart:
```bash
make stop-crc
make setup-crc
```

### Use Different Storage Class

```bash
# Check available storage classes
oc get storageclass

# Deploy with custom storage class
helm upgrade mirador-pipelines . \
  --namespace miradorstack \
  -f values.yaml \
  -f values-okd.yaml \
  --set victoriametrics.vmstorage.persistentVolume.storageClass=<class-name>
```

### Deploy to Remote OKD Cluster

If you have a remote 3-node OKD cluster:

```bash
# Login to remote cluster
oc login <remote-cluster-url>

# Skip CRC setup, just deploy
make deploy
make verify
```

## Performance Tuning

### For Development (Lower Resources)

Reduce replicas in values.yaml:

```yaml
gateway:
  replicaCount: 1  # Instead of 3

victoriametrics:
  vminsert:
    replicaCount: 1  # Instead of 3
  vmselect:
    replicaCount: 1
  vmstorage:
    replicaCount: 1
```

### For Production (Higher Resources)

Use the default 3-node configuration as-is.

## Support

For issues or questions:
1. Check the logs: `make logs`
2. Verify status: `make verify`
3. Review [DEPLOY-OKD.md](DEPLOY-OKD.md) for detailed troubleshooting
4. Check CRC documentation: https://developers.redhat.com/products/openshift-local

## Quick Reference Card

| Command | Description |
|---------|-------------|
| `make setup` | **Complete automated setup** |
| `make setup-pvs` | Create PersistentVolumes |
| `make deploy` | Deploy/upgrade the pipeline |
| `make verify` | Check all services are running |
| `make status` | Show deployment status |
| `make show-pvs` | Show PersistentVolumes status |
| `make logs` | View all pod logs |
| `make clean` | Uninstall deployment (including PVs) |
| `make stop-crc` | Stop the CRC cluster |
| `make help` | Show all available commands |

---

**Ready to deploy?** Run `make setup` and you're good to go! 🚀
