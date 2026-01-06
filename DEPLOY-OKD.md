# Deploying to OKD (OpenShift Kubernetes Distribution)

This guide covers deploying the Mirador Signals Pipeline to OKD with proper security contexts and configurations.

## Prerequisites

- OKD cluster (3+ nodes recommended)
- `oc` CLI installed and configured
- Cluster admin access (for creating namespaces and RBAC)
- Storage class available for PVCs

## OKD-Specific Considerations

### 1. Security Context Constraints (SCCs)

OKD enforces stricter security by default using SCCs. The `values-okd.yaml` file includes:
- `runAsNonRoot: true` - Prevents running as root
- `fsGroup: 1000` - Ensures PVC access permissions
- `seccompProfile` - Security profiles for containers
- `capabilities.drop: ALL` - Drops all Linux capabilities

### 2. Service Accounts

The chart creates service accounts automatically. For the gateway, RBAC is already configured for Kubernetes service discovery.

### 3. Storage Classes

Check available storage classes in your OKD cluster:
```bash
oc get storageclass
```

Update the storage class if needed:
```bash
# Edit values.yaml or override via helm
--set victoriametrics.vmstorage.persistentVolume.storageClass=<your-storage-class>
```

## Deployment Steps

### 1. Login to OKD

```bash
oc login <your-okd-api-url>
```

### 2. Create Project (Namespace)

```bash
# OKD uses 'projects' instead of namespaces
oc new-project miradorstack
```

Or use the namespace approach:
```bash
oc create namespace miradorstack
oc project miradorstack
```

### 3. Verify Cluster Resources

```bash
# Check nodes
oc get nodes

# Check storage classes
oc get storageclass

# Verify you have cluster-admin or sufficient permissions
oc auth can-i create clusterrole
```

### 4. Add Helm Repository

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
```

### 5. Update Dependencies

```bash
cd /path/to/mirador-signals-pipeline
helm dependency update
```

### 6. Deploy with OKD Values

**Standard deployment:**
```bash
helm install mirador-pipelines . \
  --namespace miradorstack \
  -f values.yaml \
  -f values-okd.yaml \
  --wait \
  --timeout 15m
```

**With custom storage class:**
```bash
helm install mirador-pipelines . \
  --namespace miradorstack \
  -f values.yaml \
  -f values-okd.yaml \
  --set victoriametrics.vmstorage.persistentVolume.storageClass=ocs-storagecluster-ceph-rbd \
  --set victoriatraces.server.persistentVolume.storageClass=ocs-storagecluster-ceph-rbd \
  --set victorialogs.server.persistentVolume.storageClass=ocs-storagecluster-ceph-rbd \
  --wait \
  --timeout 15m
```

### 7. Verify Deployment

```bash
# Check all pods
oc get pods -n miradorstack

# Check pod distribution across nodes
oc get pods -n miradorstack -o wide

# Check services
oc get svc -n miradorstack

# Check PVCs
oc get pvc -n miradorstack

# Check routes (if any are created)
oc get routes -n miradorstack
```

### 8. Verify Multi-Node Distribution

```bash
# Group pods by node
oc get pods -n miradorstack -o wide | awk 'NR>1 {print $7}' | sort | uniq -c

# Should show pods distributed across 3 nodes
# Example output:
#   8 worker-1
#   8 worker-2
#   8 worker-3
```

## Troubleshooting

### Issue 1: Pods in CrashLoopBackOff

**Symptom:** Pods fail with permission errors
```bash
oc logs <pod-name> -n miradorstack
```

**Solution:** Check if images support running as non-root user
```bash
# Verify security context
oc get pod <pod-name> -n miradorstack -o jsonpath='{.spec.securityContext}'
```

### Issue 2: PVC Binding Issues

**Symptom:** PVCs stuck in Pending state
```bash
oc get pvc -n miradorstack
oc describe pvc <pvc-name> -n miradorstack
```

**Solutions:**
1. Check storage class exists:
   ```bash
   oc get storageclass
   ```

2. Verify provisioner is working:
   ```bash
   oc get pods -n openshift-storage  # For OCS
   ```

3. Check node capacity:
   ```bash
   oc describe nodes | grep -A 5 "Allocated resources"
   ```

### Issue 3: RBAC/Permission Errors

**Symptom:** Gateway can't discover services
```bash
oc logs -n miradorstack -l app.kubernetes.io/component=gateway
```

**Solution:** Verify ClusterRole and ClusterRoleBinding
```bash
oc get clusterrole | grep mirador
oc get clusterrolebinding | grep mirador

# Check service account permissions
oc auth can-i list services --as=system:serviceaccount:miradorstack:mirador-pipelines-gateway
```

### Issue 4: Image Pull Errors

**Symptom:** ImagePullBackOff errors
```bash
oc describe pod <pod-name> -n miradorstack
```

**Solutions:**
1. Check if registry is accessible:
   ```bash
   oc run test --image=otel/opentelemetry-collector-contrib:latest --restart=Never
   ```

2. Add image pull secrets if needed:
   ```bash
   oc create secret docker-registry regcred \
     --docker-server=<registry> \
     --docker-username=<username> \
     --docker-password=<password>

   # Update values.yaml
   imagePullSecrets:
     - name: regcred
   ```

### Issue 5: SCC Violations

**Symptom:** Pods rejected due to SCC constraints
```bash
oc get events -n miradorstack | grep -i "unable to validate"
```

**Solution:** Check which SCC is assigned
```bash
oc get pod <pod-name> -n miradorstack -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Grant appropriate SCC if needed (requires cluster admin)
oc adm policy add-scc-to-user anyuid -z <service-account-name> -n miradorstack
```

## OKD-Specific Features

### Creating Routes for External Access

If you need external access to services (optional):

```bash
# Expose VictoriaMetrics vmselect for queries
oc expose svc mirador-pipelines-victoriametrics-victoria-metrics-cluster-vmselect \
  --name=vm-query \
  --port=8481

# Get the route URL
oc get route vm-query -n miradorstack
```

### Using OKD Web Console

Access the deployment via OKD web console:
1. Navigate to **Developer** → **Topology**
2. Select project: `miradorstack`
3. View pod status, logs, and metrics
4. Monitor resource usage

## Performance Tuning for OKD

### Node Selection

Use node selectors for specific workload placement:

```yaml
# In values-okd.yaml
victoriametrics:
  vmstorage:
    nodeSelector:
      node-role.kubernetes.io/worker: ""
      workload: storage
```

### Pod Priority

Set pod priority for critical workloads:

```yaml
# Create PriorityClass
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000
globalDefault: false

# Reference in values
victoriametrics:
  vmstorage:
    priorityClassName: high-priority
```

## Monitoring

### Check Resource Usage

```bash
# Pod resource usage
oc adm top pods -n miradorstack

# Node resource usage
oc adm top nodes

# PVC usage
oc get pvc -n miradorstack -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.storage}{"\n"}{end}'
```

### View Logs

```bash
# Tail logs from all gateway pods
oc logs -f -n miradorstack -l app.kubernetes.io/component=gateway --max-log-requests=10

# View logs from specific pod
oc logs -n miradorstack <pod-name>

# View previous crashed container logs
oc logs -n miradorstack <pod-name> --previous
```

## Upgrade

```bash
# Update chart dependencies
helm dependency update

# Upgrade deployment
helm upgrade mirador-pipelines . \
  --namespace miradorstack \
  -f values.yaml \
  -f values-okd.yaml \
  --wait \
  --timeout 15m

# Rollback if needed
helm rollback mirador-pipelines -n miradorstack
```

## Cleanup

```bash
# Uninstall helm release
helm uninstall mirador-pipelines -n miradorstack

# Delete PVCs
oc delete pvc --all -n miradorstack

# Delete project
oc delete project miradorstack
```

## Additional Resources

- [OKD Documentation](https://docs.okd.io/)
- [OpenShift Security Context Constraints](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
