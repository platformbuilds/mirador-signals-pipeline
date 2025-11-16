# Mirador Signals Pipeline - UAT Deployment Guide

This guide covers deploying the Mirador OpenTelemetry collector pipelines for the UAT environment.

## Architecture Overview

The UAT pipeline consists of two main components:

1. **Gateway Pipeline** (3 replicas) - Receives telemetry from applications and routes to downstream collectors
2. **Service Graph Collector** (1 replica) - Generates service graph metrics from traces

```
Applications → Gateway (3 replicas) → Service Graph Collector (1 replica) → Backends
                                    → Logs Collector
                                    → Metrics Collector
```

## Prerequisites

- Kubernetes cluster (1.24+)
- Helm 3.9+
- Namespace for deployment (e.g., `observability`)

## Deployment Steps

### 1. Create Namespace

```bash
kubectl create namespace observability
```

### 2. Deploy Gateway Pipeline

The gateway receives telemetry from applications and routes to downstream collectors.

```bash
helm install gateway ./uat-pipeline \
  --namespace observability \
  --create-namespace
```

**Default Configuration:**
- Mode: `deployment`
- Replicas: `3` (configurable)
- Resources: 1 CPU / 2Gi memory limit per pod
- Receivers: OTLP (gRPC:4317, HTTP:4318), Jaeger, Zipkin
- Exporters: Routes to servicegraph, logs, and metrics collectors

### 3. Deploy Service Graph Collector

The service graph collector generates service graph metrics from traces.

```bash
helm install servicegraph ./uat-pipeline \
  --values ./uat-pipeline/values-servicegraph.yaml \
  --namespace observability
```

**Default Configuration:**
- Mode: `deployment`
- Replicas: `1` (must be 1 for complete service graph)
- Resources: 1 CPU / 2Gi memory limit
- Connector: Service Graph with latency histograms
- Exporters: Sends traces and metrics to backends

### 4. Verify Deployments

```bash
# Check gateway pods
kubectl get pods -n observability -l app.kubernetes.io/name=gateway

# Check service graph collector pods
kubectl get pods -n observability -l app.kubernetes.io/name=servicegraph-collector

# Check services
kubectl get svc -n observability
```

Expected output:
- 3 gateway pods running
- 1 servicegraph-collector pod running
- Services for both deployments

## Configuration

### Gateway Configuration (`values.yaml`)

#### Customize Downstream Endpoints

Edit `values.yaml` to configure where gateway routes telemetry:

```yaml
downstream:
  servicegraph:
    endpoint: "servicegraph-collector.observability.svc.cluster.local:4317"
    tls:
      enabled: true
      insecure: false
      ca_file: "/etc/ssl/certs/ca.crt"
    auth:
      type: "bearer"
      bearer:
        token: "your-secret-token"

  logs:
    endpoint: "logs-collector.observability.svc.cluster.local:4317"
    tls:
      enabled: false
      insecure: true
    auth:
      type: "none"

  metrics:
    endpoint: "metrics-collector.observability.svc.cluster.local:4317"
    tls:
      enabled: false
      insecure: true
    auth:
      type: "none"
```

#### Authentication Options

**No Authentication:**
```yaml
auth:
  type: "none"
```

**Bearer Token:**
```yaml
auth:
  type: "bearer"
  bearer:
    token: "your-bearer-token"
```

**Basic Auth:**
```yaml
auth:
  type: "basic"
  basic:
    username: "admin"
    password: "secret"
```

**API Key:**
```yaml
auth:
  type: "apikey"
  apikey:
    key: "X-API-Key"
    value: "your-api-key-value"
```

#### Adjust Replica Count

```yaml
replicaCount: 3  # Change to desired number
```

#### Tune Batch Processors

For different traffic patterns, adjust batch settings:

```yaml
config:
  processors:
    batch/logs:
      timeout: 1s           # Increase for lower volume
      send_batch_size: 10000  # Decrease for lower volume
```

### Service Graph Configuration (`values-servicegraph.yaml`)

#### Configure Backend Endpoints

Edit `values-servicegraph.yaml`:

```yaml
backends:
  traces:
    endpoint: "tempo.observability.svc.cluster.local:4317"
    tls:
      enabled: true
      insecure: false
      ca_file: "/etc/ssl/certs/ca.crt"
    auth:
      type: "bearer"
      bearer:
        token: "your-tempo-token"

  metrics:
    endpoint: "prometheus.observability.svc.cluster.local:4317"
    tls:
      enabled: false
      insecure: true
    auth:
      type: "none"
```

#### Customize Service Graph Connector

Adjust latency buckets and dimensions:

```yaml
config:
  connectors:
    servicegraph:
      latency_histogram_buckets: [10ms, 50ms, 100ms, 500ms, 1s, 5s, 10s]
      dimensions:
        - http.method
        - http.status_code
        - custom.attribute
      store:
        ttl: 5s           # Increase if spans arrive out of order
        max_items: 50000  # Increase for high cardinality
```

## Upgrading

### Upgrade Gateway

```bash
helm upgrade gateway ./uat-pipeline \
  --namespace observability \
  --reuse-values
```

### Upgrade Service Graph Collector

```bash
helm upgrade servicegraph ./uat-pipeline \
  --values ./uat-pipeline/values-servicegraph.yaml \
  --namespace observability \
  --reuse-values
```

## Monitoring

### Check Collector Health

```bash
# Gateway health
kubectl port-forward -n observability svc/gateway 13133:13133
curl http://localhost:13133

# Service Graph health
kubectl port-forward -n observability svc/servicegraph-collector 13133:13133
curl http://localhost:13133
```

### View Collector Metrics

```bash
# Gateway metrics (Prometheus format)
kubectl port-forward -n observability svc/gateway 8888:8888
curl http://localhost:8888/metrics

# Service Graph metrics
kubectl port-forward -n observability svc/servicegraph-collector 8888:8888
curl http://localhost:8888/metrics
```

### View Logs

```bash
# Gateway logs
kubectl logs -n observability -l app.kubernetes.io/name=gateway --tail=100 -f

# Service Graph logs
kubectl logs -n observability -l app.kubernetes.io/name=servicegraph-collector --tail=100 -f
```

## Troubleshooting

### Gateway Not Receiving Traffic

1. Check service endpoints:
```bash
kubectl get svc -n observability gateway
kubectl get endpoints -n observability gateway
```

2. Verify receivers are listening:
```bash
kubectl logs -n observability -l app.kubernetes.io/name=gateway | grep "receiver"
```

3. Test OTLP endpoint:
```bash
kubectl port-forward -n observability svc/gateway 4317:4317
# Send test trace using grpcurl or similar tool
```

### Service Graph Not Generating Metrics

1. Verify traces are reaching service graph collector:
```bash
kubectl logs -n observability -l app.kubernetes.io/name=servicegraph-collector | grep "traces"
```

2. Check servicegraph connector:
```bash
kubectl logs -n observability -l app.kubernetes.io/name=servicegraph-collector | grep "servicegraph"
```

3. Verify both spans of a trace reach the same collector (should always be true with 1 replica)

### High Memory Usage

1. Check current memory:
```bash
kubectl top pods -n observability
```

2. Increase resource limits:
```yaml
resources:
  limits:
    memory: 4Gi  # Increase as needed
```

3. Tune batch sizes to process smaller batches:
```yaml
config:
  processors:
    batch/traces:
      send_batch_size: 512  # Reduce from 1024
```

## Uninstalling

```bash
# Remove service graph collector
helm uninstall servicegraph --namespace observability

# Remove gateway
helm uninstall gateway --namespace observability

# Optional: Remove namespace
kubectl delete namespace observability
```

## Advanced Configuration

### Using External Secrets for Authentication

Instead of hardcoding credentials in values.yaml, use Kubernetes secrets:

1. Create secret:
```bash
kubectl create secret generic otel-auth \
  --from-literal=bearer-token=your-token \
  --namespace observability
```

2. Reference in extraEnvs:
```yaml
extraEnvs:
  - name: BEARER_TOKEN
    valueFrom:
      secretKeyRef:
        name: otel-auth
        key: bearer-token
```

3. Use in config:
```yaml
config:
  exporters:
    otlp/backend:
      headers:
        authorization: "Bearer ${env:BEARER_TOKEN}"
```

### TLS with Custom CA Certificates

1. Create secret with CA cert:
```bash
kubectl create secret generic otel-ca \
  --from-file=ca.crt=/path/to/ca.crt \
  --namespace observability
```

2. Mount in values:
```yaml
extraVolumes:
  - name: ca-cert
    secret:
      secretName: otel-ca

extraVolumeMounts:
  - name: ca-cert
    mountPath: /etc/ssl/certs
    readOnly: true
```

3. Reference in config:
```yaml
downstream:
  traces:
    tls:
      enabled: true
      insecure: false
      ca_file: "/etc/ssl/certs/ca.crt"
```

## Support

For issues or questions:
- Check logs: `kubectl logs -n observability <pod-name>`
- Review configuration: `kubectl get configmap -n observability -o yaml`
- Validate with dry-run: `helm install --dry-run --debug`
