# UAT Pipeline - Changes Summary

## Overview
Modified the OpenTelemetry Collector Helm chart to create a Mirador-specific gateway and service graph pipeline for the UAT environment.

## Architecture

### Before
- Generic OTel collector chart
- Single deployment with debug exporter
- No downstream routing

### After
```
Applications
    ↓
Gateway Pipeline (3 replicas)
    ├── Traces → Service Graph Collector
    ├── Logs → Logs Collector
    └── Metrics → Metrics Collector
         ↓
Service Graph Collector (1 replica)
    ├── Traces → Tempo/Jaeger
    └── Service Graph Metrics → Prometheus/Mimir
```

## Files Modified

### 1. Chart.yaml
**Changes:**
- Name: `opentelemetry-collector` → `mirador-otel-gateway`
- Version: `0.138.1` → `0.1.0`
- Description: Updated to "Mirador Signals Gateway - OpenTelemetry Collector for UAT Environment"

**Lines changed:** 3 lines

### 2. values.yaml (Gateway Configuration)
**Major Changes:**

#### Metadata & Mode
- `nameOverride`: Set to `"gateway"`
- `mode`: Set to `"deployment"` (was empty)
- `replicaCount`: Changed from `1` to `3`

#### New Section: Downstream Configuration (lines 15-54)
Added complete downstream routing configuration with:
- Service Graph endpoint
- Logs endpoint
- Metrics endpoint
- TLS configuration support (insecure/secure with CA)
- Auth configuration (none/bearer/basic/apikey)

#### Exporters (lines 181-234)
**Removed:**
- `debug: {}` exporter

**Added:**
- `otlp/servicegraph`: Routes traces to service graph collector
  - Configurable endpoint from `.Values.downstream.servicegraph.endpoint`
  - TLS support with optional CA cert
  - Auth support (bearer/basic/apikey)

- `otlp/logs`: Routes logs to logs collector
  - Configurable endpoint
  - TLS and auth support
  - Sending queue with 10 parallel consumers for high-volume logs

- `otlp/metrics`: Routes metrics to metrics collector
  - Configurable endpoint
  - TLS and auth support

All exporters support templating with conditional auth/TLS configuration.

#### Processors (lines 241-264)
**Removed:**
- Generic `batch: {}` processor

**Added:**
- `batch/traces`: Optimized for traces
  - `timeout: 10s`
  - `send_batch_size: 1024`

- `batch/logs`: Optimized for high-volume logs
  - `timeout: 1s` (low latency)
  - `send_batch_size: 10000` (large batches)

- `batch/metrics`: Optimized for metrics
  - `timeout: 60s`
  - `send_batch_size: 8192`

#### Pipelines (lines 302-335)
**Changed all three pipelines:**

**Traces Pipeline:**
- Exporters: `debug` → `otlp/servicegraph`
- Processors: `batch` → `batch/traces`

**Logs Pipeline:**
- Exporters: `debug` → `otlp/logs`
- Processors: `batch` → `batch/logs`

**Metrics Pipeline:**
- Exporters: `debug` → `otlp/metrics`
- Processors: `batch` → `batch/metrics`

#### Resources (lines 497-503)
**Changed:**
```yaml
# Before
resources: {}

# After
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

**Total lines changed:** ~150 lines modified/added

### 3. values-servicegraph.yaml (NEW FILE)
**Purpose:** Dedicated configuration for Service Graph collector deployment

**Key Sections:**

#### Metadata
- `nameOverride: "servicegraph-collector"`
- `mode: "deployment"`
- `replicaCount: 1` (required for complete service graph)

#### Backend Configuration (lines 10-42)
- `backends.traces`: Tempo/Jaeger endpoint configuration
- `backends.metrics`: Prometheus/Mimir endpoint configuration
- Both support TLS and auth (bearer/basic/apikey)

#### Service Graph Connector (lines 61-74)
```yaml
connectors:
  servicegraph:
    latency_histogram_buckets: [2ms, 4ms, ..., 15s]
    dimensions:
      - http.method
      - http.status_code
      - rpc.grpc.status_code
    store:
      ttl: 2s
      max_items: 10000
```

#### Exporters (lines 76-115)
- `otlp/traces`: Sends traces to backend with auth/TLS
- `otlp/metrics`: Sends service graph metrics to backend with auth/TLS

#### Processors (lines 123-135)
- `memory_limiter`: Prevents OOM
- `batch/traces`: `timeout: 10s, send_batch_size: 1024`
- `batch/metrics`: `timeout: 30s, send_batch_size: 1000`

#### Receivers (lines 137-143)
- `otlp`: gRPC (4317) and HTTP (4318)

#### Pipelines (lines 154-172)
**Traces Pipeline:**
- Receivers: `otlp` (from gateway)
- Processors: `memory_limiter`, `batch/traces`
- Exporters: `servicegraph` (connector), `otlp/traces` (backend)

**Metrics/Service Graph Pipeline:**
- Receivers: `servicegraph` (connector output)
- Processors: `batch/metrics`
- Exporters: `otlp/metrics` (backend)

**Total lines:** 235 lines (new file)

### 4. DEPLOYMENT.md (NEW FILE)
**Purpose:** Comprehensive deployment and configuration guide

**Sections:**
1. Architecture Overview
2. Prerequisites
3. Deployment Steps (gateway + service graph)
4. Configuration Examples
   - Downstream endpoints
   - Authentication (none/bearer/basic/apikey)
   - TLS configuration
   - Batch tuning
5. Upgrading
6. Monitoring
7. Troubleshooting
8. Advanced Configuration
   - External secrets
   - Custom CA certificates

**Total lines:** 340 lines (new file)

## Configuration Capabilities

### Downstream Routing
All downstream endpoints are configurable via values with support for:

1. **Endpoint Configuration:**
   - Format: `host:port`
   - Supports Kubernetes service DNS
   - Supports external endpoints

2. **TLS Configuration:**
   - Insecure mode (for development)
   - Secure mode with CA certificate
   - Optional client certificates

3. **Authentication:**
   - **None**: No authentication
   - **Bearer Token**: `Authorization: Bearer <token>`
   - **Basic Auth**: `Authorization: Basic <base64(user:pass)>`
   - **API Key**: Custom header with key/value

### Batch Processing Optimization

Each signal type has optimized batch settings:

| Signal | Timeout | Batch Size | Rationale |
|--------|---------|------------|-----------|
| Traces | 10s | 1024 | Balance latency and efficiency |
| Logs | 1s | 10000 | Low latency for high volume |
| Metrics | 60s | 8192 | Can tolerate higher latency |

### High Availability

- **Gateway**: 3 replicas (configurable) for load distribution
- **Service Graph**: 1 replica (required for complete graph)

## Deployment Commands

### Gateway
```bash
helm install gateway ./uat-pipeline \
  --namespace observability \
  --create-namespace
```

### Service Graph
```bash
helm install servicegraph ./uat-pipeline \
  --values ./uat-pipeline/values-servicegraph.yaml \
  --namespace observability
```

## Key Design Decisions

1. **Separate Gateway and Service Graph**
   - Gateway: Stateless router (3 replicas)
   - Service Graph: Stateful processor (1 replica)
   - Reason: Complete trace context required for service graph

2. **Optimized Batch Processors**
   - Different settings per signal type
   - Reason: Different latency requirements and volume characteristics

3. **Flexible Authentication**
   - Support for multiple auth types
   - Reason: Different backends have different auth requirements

4. **Resource Limits**
   - Gateway: 1 CPU / 2Gi memory per pod
   - Service Graph: 1 CPU / 2Gi memory
   - Reason: Prevent OOM, enable GOMEMLIMIT optimization

5. **Templating for Exporters**
   - Helm template syntax for dynamic configuration
   - Reason: Single source of truth in values.yaml

## Migration from Default Chart

To migrate from default OTel chart:

1. Update `Chart.yaml` with new name/version
2. Set `mode: "deployment"` and `replicaCount: 3`
3. Add `downstream` configuration section
4. Update exporters from `debug` to `otlp/*`
5. Split `batch` processor into signal-specific processors
6. Update all pipelines to use new exporters/processors
7. Set resource limits

## Testing

After deployment, verify:

1. **Gateway pods running:**
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=gateway
   ```
   Expected: 3 pods in Running state

2. **Service Graph pod running:**
   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=servicegraph-collector
   ```
   Expected: 1 pod in Running state

3. **Health checks passing:**
   ```bash
   kubectl port-forward -n observability svc/gateway 13133:13133
   curl http://localhost:13133
   ```
   Expected: HTTP 200 OK

4. **Traces flowing:**
   - Send test trace to gateway OTLP endpoint (4317)
   - Verify in backend (Tempo/Jaeger)
   - Check service graph metrics in Prometheus

## Future Enhancements

Potential future modifications:

1. Add additional downstream collectors (e.g., span metrics, tail sampling)
2. Implement load balancing exporter for multi-backend fanout
3. Add Kubernetes attributes processor for metadata enrichment
4. Configure autoscaling based on queue depth
5. Add PrometheusRules for alerting on collector health
