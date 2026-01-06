# Mirador Signals Pipeline - Base Chart

> **Note**: This directory contains the **base OpenTelemetry Collector Helm chart** used by Mirador Signals Pipeline.
>
> **For complete deployment instructions, see:** [Main README](../../README.md)

## About This Chart

This is the **reusable base chart** that provides OpenTelemetry Collector deployment capabilities. The umbrella chart (`mirador-signals-pipeline`) uses this chart **four times** with different configurations via aliases to create the complete pipeline stack:

1. **Gateway** (3 replicas) - High-throughput ingestion
2. **ServiceGraph** (1 replica) - Service topology generation
3. **SpanMetrics** (1 replica) - RED metrics extraction
4. **IsolationForest** (3 replicas) - ML anomaly detection

## Chart Capabilities

### Deployment Modes
- `deployment` (default for Gateway, IsolationForest)
- `daemonset` (for node-level collection)
- `statefulset` (for persistent storage needs)

### Key Features
- **OTLP-only receivers** (gRPC + HTTP on ports 4317/4318)
- **K8s-native loadbalancing** with service discovery
- **RBAC support** for Kubernetes API access
- **Autoscaling** (HPA compatible)
- **Resource limits** and GOMEMLIMIT tuning
- **Port configuration** (Jaeger/Zipkin ports disabled by default)

## Quick Reference

### Single Command Deployment

Deploy the complete umbrella chart:

```bash
# From repository root
cd ../..
helm install mirador . --namespace miradorstack --create-namespace
```

This deploys:
- Gateway (3 replicas)
- ServiceGraph (1 replica)
- SpanMetrics (1 replica)
- IsolationForest (3 replicas)

**Total: 8 pods**

### Verify Deployment

```bash
kubectl get pods -n miradorstack

# Expected:
# mirador-gateway-*           3/3 Running
# mirador-isolationforest-*   3/3 Running
# mirador-servicegraph-*      1/1 Running
# mirador-spanmetrics-*       1/1 Running
```

## Architecture Overview

This base chart is instantiated 4 times to create this flow:

```
Applications → Gateway → ├─► ServiceGraph → VictoriaMetrics/VictoriaTraces
                         ├─► SpanMetrics → IsolationForest → VictoriaMetrics
                         └─► IsolationForest (direct metrics) → VictoriaMetrics
```

## Configuration Examples

### Gateway Configuration

```yaml
gateway:
  enabled: true
  replicaCount: 3
  mode: deployment

  clusterRole:
    create: true  # Required for K8s service discovery

  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: ${env:MY_POD_IP}:4317
          http:
            endpoint: ${env:MY_POD_IP}:4318

    exporters:
      loadbalancing/servicegraph:
        routing_key: "traceID"
        resolver:
          k8s:
            service: "mirador-servicegraph"
            ports: [4317]

      loadbalancing/isolationforest-metrics:
        routing_key: "resource"
        resolver:
          k8s:
            service: "mirador-isolationforest"
            ports: [4317]

    pipelines:
      traces:
        receivers: [otlp]
        exporters: [loadbalancing/servicegraph, loadbalancing/spanmetrics]

      metrics:
        receivers: [otlp]
        exporters: [loadbalancing/isolationforest-metrics]

      logs:
        receivers: [otlp]
        exporters: [otlp/logs]
```

### IsolationForest Configuration

```yaml
isolationforest:
  enabled: true
  replicaCount: 3  # Scaled for HA + loadbalancing
  mode: deployment

  resources:
    limits:
      cpu: 2000m
      memory: 4Gi

  config:
    processors:
      isolationforest: {}  # ML processor

    exporters:
      otlp/metrics:
        endpoint: "victoriametrics.miradorstack.svc.cluster.local:4317"

    pipelines:
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, isolationforest, batch/metrics]
        exporters: [otlp/metrics]
```

## Port Configuration

### Default Ports (Enabled)

- **4317** - OTLP gRPC
- **4318** - OTLP HTTP
- **8888** - Prometheus metrics (collector internal metrics)

### Legacy Ports (Disabled by Default)

The following ports are **disabled** and can be re-enabled if needed:

```yaml
ports:
  jaeger-compact:
    enabled: false  # 6831/UDP
  jaeger-thrift:
    enabled: false  # 14268/TCP
  jaeger-grpc:
    enabled: false  # 14250/TCP
  zipkin:
    enabled: false  # 9411/TCP
```

**Why disabled?**
- OTLP is the modern standard
- Reduced attack surface
- Simpler maintenance
- Better performance

## RBAC Configuration

K8s-native loadbalancing requires ClusterRole permissions:

```yaml
clusterRole:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["services", "endpoints"]
      verbs: ["get", "list", "watch"]
```

This is **automatically configured** for the Gateway collector.

## Resource Management

### Recommended Resources

**Gateway (high-throughput):**
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

**IsolationForest (ML processing):**
```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 2Gi
```

**ServiceGraph/SpanMetrics:**
```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

### GOMEMLIMIT

Enabled by default to prevent OOM:

```yaml
useGOMEMLIMIT: true  # Sets GOMEMLIMIT to 80% of memory limit
```

## Scaling

### Horizontal Scaling

```yaml
# Gateway - scale for throughput
gateway:
  replicaCount: 5

# IsolationForest - scale for ML capacity
isolationforest:
  replicaCount: 5

# ServiceGraph - MUST be 1 for complete graph
servicegraph:
  replicaCount: 1

# SpanMetrics - can scale if needed
spanmetrics:
  replicaCount: 3
```

### Autoscaling

```yaml
gateway:
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

## Troubleshooting

### Chart Dependencies

```bash
# Update dependencies
helm dependency update ../../

# Build dependencies
helm dependency build ../../
```

### Pod Issues

```bash
# Check pod status
kubectl get pods -n miradorstack

# Describe specific pod
kubectl describe pod -n miradorstack <pod-name>

# View logs
kubectl logs -n miradorstack <pod-name>

# Check resource usage
kubectl top pods -n miradorstack
```

### Service Discovery

```bash
# Check endpoints discovered by K8s resolver
kubectl get endpoints -n miradorstack

# Check ClusterRole
kubectl get clusterrole | grep mirador

# Check ClusterRoleBinding
kubectl get clusterrolebinding | grep mirador
```

### Configuration Validation

```bash
# Test configuration locally
helm template mirador ../../ --debug

# Validate against cluster
helm install mirador ../../ --dry-run --debug
```

## Advanced Configuration

### Custom Batch Processing

```yaml
config:
  processors:
    batch/traces:
      timeout: 10s
      send_batch_size: 1024

    batch/metrics:
      timeout: 60s
      send_batch_size: 8192

    batch/logs:
      timeout: 1s
      send_batch_size: 10000
```

### Memory Limiter

```yaml
config:
  processors:
    memory_limiter:
      check_interval: 5s
      limit_percentage: 80
      spike_limit_percentage: 25
```

### Custom Exporters

```yaml
config:
  exporters:
    otlp/custom:
      endpoint: "custom-backend.example.com:4317"
      tls:
        insecure: false
        ca_file: /etc/ssl/certs/ca.crt
      auth:
        authenticator: bearertokenauth/custom
```

## Full Documentation

- **Main Documentation**: [README.md](../../README.md)
- **Configuration Examples**: See umbrella chart values.yaml
- **Troubleshooting Guide**: Main README
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/collector/

## Development

### Testing Changes

```bash
# Install with custom values
helm install test ../../ -f test-values.yaml --namespace test

# Upgrade to test changes
helm upgrade test ../../ -f test-values.yaml --namespace test

# Cleanup
helm uninstall test --namespace test
```

### Linting

```bash
helm lint ../../
```

## Support

For issues with this chart or the Mirador Signals Pipeline:

- **Main README**: [../../README.md](../../README.md)
- **Issues**: File issues in the main repository
- **OpenTelemetry Community**: https://opentelemetry.io/community/
