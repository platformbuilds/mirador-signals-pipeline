# Mirador Pipelines - Umbrella Chart

Single Helm release that deploys the entire Mirador signals pipeline stack:
- **Gateway Pipeline** (3 replicas) - Receives telemetry from applications
- **Service Graph Collector** (1 replica) - Generates service topology metrics (Use Case 1)
- **Span Metrics Collector** (1 replica) - Generates RED metrics from traces (Use Case 2)
- **Isolation Forest Processor** (1 replica) - Anomaly detection on span metrics (Use Case 2)

## Quick Start

### Single Command Deployment

```bash
# Deploy the entire stack
helm install mirador-pipelines ./mirador-pipelines \
  --namespace observability \
  --create-namespace
```

That's it! This single command deploys both the gateway and service graph collectors as a connected stack.

## What Gets Deployed

### Gateway Collector
- **Name:** `mirador-pipelines-gateway`
- **Replicas:** 3
- **Receivers:** OTLP (4317/4318), Jaeger (14250, 14268, 6831), Zipkin (9411)
- **Function:** Fan-out traces to service graph AND span metrics collectors

### Service Graph Collector (Use Case 1)
- **Name:** `mirador-pipelines-servicegraph`
- **Replicas:** 1
- **Receivers:** OTLP (4317/4318)
- **Function:** Generates service topology metrics and forwards traces to backend

### Span Metrics Collector (Use Case 2)
- **Name:** `mirador-pipelines-spanmetrics`
- **Replicas:** 1
- **Receivers:** OTLP (4317/4318)
- **Function:** Generates RED metrics (Rate, Error, Duration) from traces and forwards to isolation forest

### Isolation Forest Processor (Use Case 2)
- **Name:** `mirador-pipelines-isolationforest`
- **Replicas:** 1
- **Receivers:** OTLP (4317/4318)
- **Function:** Anomaly detection on span metrics, exports enriched metrics to sink

## Verify Deployment

```bash
# Check all pods
kubectl get pods -n observability

# Expected output:
# mirador-pipelines-gateway-xxx-yyy         1/1   Running   0   30s  (x3)
# mirador-pipelines-servicegraph-xxx-yyy    1/1   Running   0   30s  (x1)
# mirador-pipelines-spanmetrics-xxx-yyy     1/1   Running   0   30s  (x1)
# mirador-pipelines-isolationforest-xxx-yyy 1/1   Running   0   30s  (x1)

# Check services
kubectl get svc -n observability

# Expected output:
# mirador-pipelines-gateway         ClusterIP   10.x.x.x   <none>        4317/TCP,4318/TCP,...   30s
# mirador-pipelines-servicegraph    ClusterIP   10.x.x.x   <none>        4317/TCP,4318/TCP       30s
```

## Configuration

### Load Balancing Exporters (Default)

The gateway uses **load balancing exporters** by default for optimal traffic distribution to downstream collectors:

**Benefits:**
- Automatic pod discovery via DNS resolution
- TraceID-based routing ensures complete traces go to the same backend
- Better load distribution across downstream collector replicas
- Automatic failover and health checking

**Configuration:**
```yaml
gateway:
  config:
    exporters:
      loadbalancing/servicegraph:
        routing_key: "traceID"  # Options: traceID, service, resource
        protocol:
          otlp:
            timeout: 10s
        resolver:
          dns:
            hostname: "mirador-pipelines-servicegraph.observability.svc.cluster.local"
            port: 4317
            interval: 5s  # DNS refresh interval
```

**Alternative: Static Resolver**
For fixed backend lists:
```yaml
loadbalancing/servicegraph:
  routing_key: "traceID"
  protocol:
    otlp:
      timeout: 10s
  resolver:
    static:
      hostnames:
      - "servicegraph-backend-1:4317"
      - "servicegraph-backend-2:4317"
```

**Alternative: Kubernetes Service Resolver**
For direct pod discovery (requires RBAC):
```yaml
loadbalancing/servicegraph:
  routing_key: "traceID"
  protocol:
    otlp:
      timeout: 10s
  resolver:
    k8s:
      service: "mirador-pipelines-servicegraph"
      ports: [4317]
```

**Fallback to Standard OTLP:**
To disable load balancing and use standard OTLP exporters:
```yaml
gateway:
  config:
    pipelines:
      traces:
        exporters: [otlp/servicegraph, otlp/spanmetrics]  # Change from loadbalancing/* to otlp/*
```

### Customize Backend Endpoints

Edit `values.yaml` to configure where telemetry is sent:

```yaml
# Gateway routes logs and metrics to backends
gateway:
  config:
    exporters:
      otlp/logs:
        endpoint: "loki.mycompany.com:4317"  # Your logs backend
      otlp/metrics:
        endpoint: "prometheus.mycompany.com:4317"  # Your metrics backend

# Service graph sends to final backends
servicegraph:
  config:
    exporters:
      otlp/traces:
        endpoint: "tempo.mycompany.com:4317"  # Your traces backend
      otlp/metrics:
        endpoint: "prometheus.mycompany.com:4317"  # Your metrics backend
```

### Adjust Replica Counts

```yaml
gateway:
  replicaCount: 5  # Scale up gateway for higher load

servicegraph:
  replicaCount: 1  # Must remain 1 for complete service graph
```

### Enable/Disable Components

```yaml
gateway:
  enabled: true  # Set to false to deploy only service graph

servicegraph:
  enabled: true  # Set to false to deploy only gateway
```

## Upgrade

```bash
# Upgrade the entire stack
helm upgrade mirador-pipelines ./mirador-pipelines \
  --namespace observability \
  --reuse-values
```

## Uninstall

```bash
# Remove entire stack with single command
helm uninstall mirador-pipelines --namespace observability
```

## Advanced Configuration

### Custom Values File

Create a custom values file for your environment:

```yaml
# custom-values.yaml
gateway:
  replicaCount: 5
  resources:
    limits:
      memory: 4Gi
  config:
    exporters:
      otlp/logs:
        endpoint: "my-logs.example.com:4317"

servicegraph:
  config:
    exporters:
      otlp/traces:
        endpoint: "my-tempo.example.com:4317"
    connectors:
      servicegraph:
        latency_histogram_buckets: [10ms, 50ms, 100ms, 500ms, 1s, 5s]
```

Deploy with custom values:
```bash
helm install mirador-pipelines ./mirador-pipelines \
  --namespace observability \
  -f custom-values.yaml
```

### TLS and Authentication

To configure TLS and auth, you'll need to modify the `config.exporters` section in values.yaml for each exporter. See the uat-pipeline DEPLOYMENT.md for detailed auth examples.

## Monitoring

### View Logs

```bash
# Gateway logs
kubectl logs -n observability -l app.kubernetes.io/name=mirador-otel-gateway -l app.kubernetes.io/instance=mirador-pipelines-gateway

# Service Graph logs
kubectl logs -n observability -l app.kubernetes.io/name=mirador-otel-gateway -l app.kubernetes.io/instance=mirador-pipelines-servicegraph
```

### Port Forward for Testing

```bash
# Forward gateway OTLP port
kubectl port-forward -n observability svc/mirador-pipelines-gateway 4317:4317

# Forward service graph OTLP port
kubectl port-forward -n observability svc/mirador-pipelines-servicegraph 4318:4318
```

## Architecture

```
Applications
    │
    ├─── OTLP (4317/4318)
    ├─── Jaeger (14250, 14268, 6831)
    └─── Zipkin (9411)
         │
         ▼
┌──────────────────────────────────────────────────────────┐
│  Gateway (3 replicas)                                    │
│  Service: mirador-pipelines-gateway                      │
├──────────────────────────────────────────────────────────┤
│ Fan-out traces to:                                       │
│  - Service Graph (Use Case 1)                            │
│  - Span Metrics (Use Case 2)                             │
│  Plus:                                                   │
│  - Logs → Logs Backend                                   │
│  - Metrics → Metrics Backend                             │
└────────┬─────────────────────────┬─────────────────────┘
         │                         │
         │ Use Case 1              │ Use Case 2
         ▼                         ▼
┌────────────────────────┐  ┌────────────────────────────┐
│ Service Graph          │  │  Span Metrics              │
│ (1 replica)            │  │  (1 replica)               │
├────────────────────────┤  ├────────────────────────────┤
│ Generates service      │  │ Generates RED metrics      │
│ topology metrics       │  │ (Rate, Error, Duration)    │
│                        │  │                            │
│ Outputs:               │  │ Outputs:                   │
│  - Traces → Backend    │  │  - Traces → Backend        │
│  - Metrics → Prometheus│  │  - Metrics → Isolation     │
└────────────────────────┘  └─────────┬──────────────────┘
                                      │
                                      ▼
                           ┌──────────────────────────────┐
                           │  Isolation Forest            │
                           │  (1 replica)                 │
                           ├──────────────────────────────┤
                           │ Anomaly detection on         │
                           │ span metrics using ML        │
                           │                              │
                           │ Outputs:                     │
                           │  - Enriched Metrics → Sink   │
                           └──────────────────────────────┘
```

## Troubleshooting

### Chart Not Found

If you get "chart not found", run:
```bash
helm dependency build ./mirador-pipelines
```

### Pods Not Starting

Check events:
```bash
kubectl describe pods -n observability -l app.kubernetes.io/instance=mirador-pipelines
```

### Service Graph Not Receiving Traces

Check gateway is routing to correct endpoint:
```bash
kubectl logs -n observability -l app.kubernetes.io/instance=mirador-pipelines-gateway | grep servicegraph
```

The endpoint should be: `mirador-pipelines-servicegraph.observability.svc.cluster.local:4317`
