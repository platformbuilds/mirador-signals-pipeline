# Mirador Signals Pipeline - Umbrella Chart

Enterprise-grade OpenTelemetry pipeline for **terabyte-scale** observability with ML-powered anomaly detection.

**Single Helm release deploys:**
- **Gateway Pipeline** (3 replicas) - High-throughput ingestion with K8s-native load balancing
- **Service Graph Collector** (1 replica) - Service topology metrics generation
- **Span Metrics Collector** (1 replica) - RED metrics extraction from traces
- **Isolation Forest Processor** (3 replicas) - ML-based anomaly detection on all metrics

## Key Features

✅ **Zero Duplication** - Single-export architecture eliminates metric duplication at terabyte scale
✅ **Complete Anomaly Coverage** - ALL metrics (application + trace-derived) get ML analysis
✅ **K8s-Native** - Direct pod discovery via Kubernetes API, no DNS overhead
✅ **OTLP-Only** - Modern protocol support (gRPC + HTTP), legacy protocols removed
✅ **Production Backends** - VictoriaMetrics, VictoriaTraces, Cassandra integration

## Quick Start

### Prerequisites

- Kubernetes cluster (v1.19+)
- Helm 3.x
- kubectl configured

### Single Command Deployment

```bash
# Install from repository root
helm install mirador . --namespace miradorstack --create-namespace
```

That's it! This deploys all 8 pods (3 gateway + 3 isolationforest + 1 servicegraph + 1 spanmetrics).

### Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n miradorstack

# Expected output:
# NAME                                          READY   STATUS
# mirador-gateway-*                             3/3     Running
# mirador-isolationforest-*                     3/3     Running
# mirador-servicegraph-*                        1/1     Running
# mirador-spanmetrics-*                         1/1     Running

# Check services
kubectl get svc -n miradorstack

# Expected output:
# NAME                       TYPE        PORT(S)
# mirador-gateway            ClusterIP   8888,4317,4318
# mirador-isolationforest    ClusterIP   8888,4317,4318
# mirador-servicegraph       ClusterIP   8888,4317,4318
# mirador-spanmetrics        ClusterIP   8888,4317,4318
```

## Architecture

### Complete Data Flow

```
Applications
    │
    ├─── OTLP Traces ────────┐
    ├─── OTLP Metrics ───┐   │
    └─── OTLP Logs ──┐   │   │
                     │   │   │
                     ▼   ▼   ▼
          ┌───────────────────────────┐
          │ Gateway (3 replicas)      │
          │ K8s Loadbalancing         │
          └─────────┬─────────────────┘
                    │
    ┌───────────────┼───────────────────┐
    │               │                   │
    │ TRACES        │ METRICS           │ LOGS
    │ (fan-out)     │ (single-path)     │
    │               │                   │
    ▼               ▼                   ▼
┌───┴───┐   IsolationForest       Cassandra
│       │    (3 replicas)           (logs)
│       │         │
│       │         ▼
│       │   VictoriaMetrics
├─► ServiceGraph  (all metrics
│       │ │        + anomaly
│       │ │        scores)
│       │ └──► VictoriaTraces
│       │
│       └────► VictoriaMetrics
│              (topology)
│
└─► SpanMetrics
        │ │
        │ └──► VictoriaTraces
        │
        └────► IsolationForest
                    │
                    └──► VictoriaMetrics
                         (RED + anomalies)
```

### Component Details

#### Gateway Collector
- **Replicas:** 3 (HA + load distribution)
- **Receivers:** OTLP gRPC (4317), OTLP HTTP (4318)
- **Function:**
  - Fan-out traces to ServiceGraph AND SpanMetrics
  - Route ALL metrics through IsolationForest (zero duplication)
  - Forward logs to Cassandra
- **RBAC:** ClusterRole for K8s service discovery

#### Service Graph Collector
- **Replicas:** 1 (must be singleton for complete graph)
- **Receivers:** OTLP (4317/4318)
- **Function:**
  - Generate service topology metrics from trace spans
  - Forward traces to VictoriaTraces
  - Export topology metrics to VictoriaMetrics

#### Span Metrics Collector
- **Replicas:** 1
- **Receivers:** OTLP (4317/4318)
- **Function:**
  - Extract RED metrics (Rate, Error, Duration) from traces
  - Forward traces to VictoriaTraces
  - Send RED metrics to IsolationForest for anomaly detection

#### Isolation Forest Processor
- **Replicas:** 3 (scaled for HA + loadbalancing)
- **Receivers:** OTLP (4317/4318)
- **Input Sources:**
  - Application metrics (from Gateway)
  - RED metrics (from SpanMetrics)
- **Function:**
  - ML-based anomaly detection on all metrics
  - Enrich metrics with anomaly scores and flags
  - Export to VictoriaMetrics
- **Output Example:**
  ```
  http_requests_total{
    service="api",
    endpoint="/users",
    anomaly_score="0.85",    ← Added by ML
    is_anomaly="true"         ← Added by ML
  } 1500
  ```

## Backend Integration

### Backend Services Required

This chart deploys the **telemetry pipeline only**. Deploy these backends separately:

| Service | Purpose | Recommended |
|---------|---------|-------------|
| **VictoriaMetrics** | Metrics storage | [VictoriaMetrics Helm Chart](https://github.com/VictoriaMetrics/helm-charts) |
| **VictoriaTraces** | Traces storage | [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) or custom setup |
| **Cassandra** | Logs storage | [Cassandra Operator](https://github.com/k8ssandra/cass-operator) + OTLP adapter |

### Backend Endpoints

Configure in [values.yaml](values.yaml):

```yaml
# Gateway backends
gateway:
  config:
    exporters:
      otlp/logs:
        endpoint: "cassandra-logs.miradorstack.svc.cluster.local:4317"
      # metrics go through isolationforest (no direct backend)

# ServiceGraph backends
servicegraph:
  config:
    exporters:
      otlp/traces:
        endpoint: "victoriatraces.miradorstack.svc.cluster.local:4317"
      otlp/metrics:
        endpoint: "victoriametrics.miradorstack.svc.cluster.local:4317"

# SpanMetrics backends
spanmetrics:
  config:
    exporters:
      otlp/traces:
        endpoint: "victoriatraces.miradorstack.svc.cluster.local:4317"
      # metrics go to isolationforest (internal)

# IsolationForest backend
isolationforest:
  config:
    exporters:
      otlp/metrics:
        endpoint: "victoriametrics.miradorstack.svc.cluster.local:4317"
```

## Configuration

### Load Balancing (K8s-Native)

Gateway uses Kubernetes-native service discovery for optimal performance:

**Benefits:**
- Direct pod discovery via K8s API (no DNS lookups)
- TraceID-based routing for complete trace correlation
- Resource-based routing for consistent anomaly baselines
- Automatic failover and health checking

**Example Configuration:**

```yaml
gateway:
  config:
    exporters:
      # Traces: TraceID-based routing
      loadbalancing/servicegraph:
        routing_key: "traceID"
        resolver:
          k8s:
            service: "mirador-pipelines-servicegraph"
            ports: [4317]

      # Metrics: Resource-based routing
      loadbalancing/isolationforest-metrics:
        routing_key: "resource"
        resolver:
          k8s:
            service: "mirador-pipelines-isolationforest"
            ports: [4317]
```

### Scaling

```yaml
gateway:
  replicaCount: 5  # Scale for higher ingestion throughput

isolationforest:
  replicaCount: 5  # Scale for more ML processing capacity
  resources:
    limits:
      cpu: 4000m
      memory: 8Gi

servicegraph:
  replicaCount: 1  # Must be 1 for complete service graph

spanmetrics:
  replicaCount: 1  # Can scale if needed
```

### Protocol Configuration

**OTLP-Only (Default):**
```yaml
gateway:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: ${env:MY_POD_IP}:4317
          http:
            endpoint: ${env:MY_POD_IP}:4318
```

Legacy Jaeger and Zipkin receivers have been removed for:
- Reduced attack surface
- Simpler maintenance
- Better performance
- Modern protocol focus

### Enable/Disable Components

```yaml
gateway:
  enabled: true

servicegraph:
  enabled: true  # Disable if you don't need topology metrics

spanmetrics:
  enabled: true  # Disable if you don't need RED metrics

isolationforest:
  enabled: true  # Disable if you don't need anomaly detection
```

## Monitoring

### View Logs

```bash
# Gateway logs
kubectl logs -n miradorstack -l app.kubernetes.io/component=gateway

# IsolationForest logs
kubectl logs -n miradorstack -l app.kubernetes.io/component=isolationforest

# Check for errors
kubectl logs -n miradorstack --all-containers | grep -i error
```

### Metrics Endpoints

All collectors expose Prometheus metrics on port 8888:

```bash
# Port-forward to scrape metrics
kubectl port-forward -n miradorstack svc/mirador-gateway 8888:8888

# Curl metrics endpoint
curl http://localhost:8888/metrics
```

### Send Test Data

```bash
# Port-forward gateway OTLP port
kubectl port-forward -n miradorstack svc/mirador-gateway 4317:4317

# Send test trace (requires grpcurl or similar)
grpcurl -d '{"resource_spans":[...]}' \
  -plaintext localhost:4317 \
  opentelemetry.proto.collector.trace.v1.TraceService/Export
```

## Upgrade

```bash
# Upgrade to latest configuration
helm upgrade mirador . --namespace miradorstack

# Upgrade with custom values
helm upgrade mirador . --namespace miradorstack -f custom-values.yaml

# Upgrade and wait for rollout
helm upgrade mirador . --namespace miradorstack --wait --timeout 5m
```

## Uninstall

```bash
# Remove entire pipeline
helm uninstall mirador --namespace miradorstack

# Optionally delete namespace
kubectl delete namespace miradorstack
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pods -n miradorstack

# Check resource constraints
kubectl top pods -n miradorstack
```

### Gateway Not Forwarding Traces

```bash
# Check loadbalancing resolver
kubectl logs -n miradorstack -l app.kubernetes.io/component=gateway | grep -i "resolver\|endpoint"

# Verify downstream services exist
kubectl get svc -n miradorstack mirador-servicegraph
kubectl get svc -n miradorstack mirador-spanmetrics
```

### IsolationForest Not Receiving Metrics

```bash
# Check gateway is routing to isolationforest
kubectl logs -n miradorstack -l app.kubernetes.io/component=gateway | grep isolationforest

# Check isolationforest endpoints discovered
kubectl get endpoints -n miradorstack mirador-isolationforest

# Expected: 3 endpoints (10.x.x.x:4317)
```

### Backend Connection Errors

Expected if backends not deployed yet:
```
error: rpc error: code = Unavailable desc = connection error:
  dial tcp: lookup victoriametrics.miradorstack.svc.cluster.local: no such host
```

**Solution:** Deploy backend services (VictoriaMetrics, VictoriaTraces, Cassandra).

### Chart Dependencies Missing

```bash
# Update chart dependencies
helm dependency update .

# Build dependencies
helm dependency build .
```

## Performance Tuning

### High-Volume Metrics

```yaml
gateway:
  config:
    processors:
      batch/metrics:
        timeout: 30s          # Reduce for lower latency
        send_batch_size: 16384 # Increase for higher throughput

isolationforest:
  replicaCount: 5             # Scale out
  resources:
    limits:
      memory: 8Gi             # Increase for larger ML models
```

### Trace Sampling

```yaml
gateway:
  config:
    processors:
      probabilistic_sampler:
        sampling_percentage: 10  # Sample 10% of traces
```

## Security

### TLS Configuration

```yaml
gateway:
  config:
    exporters:
      loadbalancing/servicegraph:
        protocol:
          otlp:
            tls:
              insecure: false
              ca_file: /etc/ssl/certs/ca.crt
              cert_file: /etc/ssl/certs/client.crt
              key_file: /etc/ssl/private/client.key
```

### Network Policies

```yaml
gateway:
  networkPolicy:
    enabled: true
    allowIngressFrom:
      - namespaceSelector:
          matchLabels:
            name: application-namespace
```

## Advanced Topics

### Custom Processors

Add custom processors to any collector:

```yaml
isolationforest:
  config:
    processors:
      attributes:
        actions:
          - key: environment
            value: production
            action: insert

      filter/drop-health-checks:
        metrics:
          exclude:
            match_type: regexp
            metric_names:
              - "^http_requests_total.*healthz.*$"
```

### Multi-Cluster Setup

Deploy in multiple clusters with shared backends:

```yaml
# Cluster A
gateway:
  config:
    exporters:
      otlp/logs:
        endpoint: "cassandra-logs.shared-backends.svc.cluster.local:4317"

# Cluster B
gateway:
  config:
    exporters:
      otlp/logs:
        endpoint: "cassandra-logs.shared-backends.svc.cluster.local:4317"
```

## Contributing

See [CONTRIBUTING.md](charts/otel-collector/CONTRIBUTING.md) for development guidelines.

## License

This chart packages the [OpenTelemetry Collector](https://github.com/open-telemetry/opentelemetry-collector) under its respective license.

## Support

- **Issues:** [GitHub Issues](https://github.com/your-org/mirador-signals-pipeline/issues)
- **Discussions:** [GitHub Discussions](https://github.com/your-org/mirador-signals-pipeline/discussions)
- **Docs:** [Full Documentation](https://your-org.github.io/mirador-signals-pipeline/)
