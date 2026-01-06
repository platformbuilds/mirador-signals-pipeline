# Mirador Stack - Docker Compose Deployment

Complete observability stack with VictoriaMetrics, VictoriaTraces, and VictoriaLogs, designed for single-node and multi-node cluster deployments.

## Architecture

### Components

#### Storage Layer (Victoria Stack)
- **VictoriaMetrics Cluster**: Metrics storage (vminsert, vmselect, vmstorage)
- **VictoriaTraces Cluster**: Traces storage (vtinsert, vtselect, vtstorage)
- **VictoriaLogs Cluster**: Logs storage (vlinsert, vlselect, vlstorage)

#### Processing Layer (OTEL Collectors)
- **Gateway**: OTLP endpoint for receiving telemetry
- **Service Graph**: Generates service topology from traces
- **Span Metrics**: Generates RED metrics from traces
- **Isolation Forest**: Anomaly detection on metrics
- **Adapters**: OTLP to Victoria format conversion (vmadapter, vlogadapter)

#### Load Balancing
- **HAProxy**: Load balances traffic across nodes and provides unified access points

## Quick Start (Single Node)

### Prerequisites
- Docker Engine 20.10+
- Docker Compose v2.0+
- 4GB+ RAM available
- 20GB+ disk space

### Deploy

```bash
cd docker-compose
make up
```

### Access Points

| Service | URL | Description |
|---------|-----|-------------|
| OTLP gRPC | `localhost:4317` | Send traces/metrics/logs |
| OTLP HTTP | `localhost:4318` | Send telemetry via HTTP |
| HAProxy Stats | `http://localhost:8404` | Load balancer stats (admin/admin) |
| Gateway Metrics | `http://localhost:8888/metrics` | OTEL collector metrics |
| VictoriaMetrics | `http://localhost:8481` | Query metrics |
| VictoriaTraces | `http://localhost:8483` | Query traces |
| VictoriaLogs | `http://localhost:9471` | Query logs |

### Common Commands

```bash
# View logs
make logs

# Check health
make health

# Test connectivity
make test

# Stop stack
make down

# Clean everything (including data)
make clean
```

## Multi-Node Cluster Setup

### Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│     Node 1      │    │     Node 2      │    │     Node 3      │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │   HAProxy   │◄┼────┼─┤   HAProxy   │◄┼────┼─┤   HAProxy   │ │
│ └──────┬──────┘ │    │ └──────┬──────┘ │    │ └──────┬──────┘ │
│        │        │    │        │        │    │        │        │
│ ┌──────▼──────┐ │    │ ┌──────▼──────┐ │    │ ┌──────▼──────┐ │
│ │   Gateway   │ │    │ │   Gateway   │ │    │ │   Gateway   │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│ Victoria Stack  │    │ Victoria Stack  │    │ Victoria Stack  │
│ (All Services)  │    │ (All Services)  │    │ (All Services)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Bootstrap 3-Node Cluster

#### Step 1: Generate Configuration

```bash
make multi-node-setup
```

This creates:
- `node1/` - Configuration for Node 1
- `node2/` - Configuration for Node 2
- `node3/` - Configuration for Node 3

#### Step 2: Configure IPs

Edit each node's `.env` file:

**node1/.env:**
```env
NODE_NAME=node1
NODE_IP=192.168.1.101    # This node's IP
NODE1_IP=192.168.1.101   # Node 1 IP
NODE2_IP=192.168.1.102   # Node 2 IP
NODE3_IP=192.168.1.103   # Node 3 IP
```

**node2/.env:**
```env
NODE_NAME=node2
NODE_IP=192.168.1.102
NODE1_IP=192.168.1.101
NODE2_IP=192.168.1.102
NODE3_IP=192.168.1.103
```

**node3/.env:**
```env
NODE_NAME=node3
NODE_IP=192.168.1.103
NODE1_IP=192.168.1.101
NODE2_IP=192.168.1.102
NODE3_IP=192.168.1.103
```

#### Step 3: Update HAProxy Configuration

Edit `nodeX/haproxy-nodeX.cfg` to add backend servers for each node.

Example for Node 1 (`node1/haproxy-node1.cfg`):

```haproxy
backend otlp_grpc_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server node1 ${NODE1_IP}:4317 check
    server node2 ${NODE2_IP}:4317 check
    server node3 ${NODE3_IP}:4317 check
```

Repeat for all backends (VictoriaMetrics, VictoriaTraces, VictoriaLogs).

#### Step 4: Deploy to Each Node

**On Node 1:**
```bash
# Copy node1 directory to Node 1 machine
scp -r node1/* node1-host:/path/to/mirador/docker-compose/

# SSH to Node 1
ssh node1-host

# Deploy
cd /path/to/mirador/docker-compose
make node1
```

**On Node 2:**
```bash
scp -r node2/* node2-host:/path/to/mirador/docker-compose/
ssh node2-host
cd /path/to/mirador/docker-compose
make node2
```

**On Node 3:**
```bash
scp -r node3/* node3-host:/path/to/mirador/docker-compose/
ssh node3-host
cd /path/to/mirador/docker-compose
make node3
```

### Testing Multi-Node Cluster

1. **Check HAProxy stats** on any node: `http://<node-ip>:8404`
2. **Send telemetry** to any node's HAProxy: `<node-ip>:4317`
3. **Query data** from any node's VictoriaMetrics: `http://<node-ip>:8481`

## Configuration

### Environment Variables

Edit `.env` to customize:

```env
# Retention periods
VM_RETENTION=30d        # Metrics retention
VT_RETENTION=30d        # Traces retention
VL_RETENTION=30d        # Logs retention

# Storage paths (inside containers)
VM_STORAGE_PATH=/victoria-metrics-data
VT_STORAGE_PATH=/victoria-traces-data
VL_STORAGE_PATH=/victoria-logs-data
```

### OTEL Collector Configuration

OTEL collector configs are in `configs/otel-collector/`:

- `gateway-config.yaml` - Main OTLP receiver
- `servicegraph-config.yaml` - Service graph generation
- `spanmetrics-config.yaml` - Span metrics generation
- `isolationforest-config.yaml` - Anomaly detection
- `vmadapter-config.yaml` - VictoriaMetrics adapter
- `vlogadapter-config.yaml` - VictoriaLogs adapter

### HAProxy Configuration

Edit `haproxy/haproxy.cfg` to:
- Change load balancing algorithms
- Add/remove backend servers
- Adjust health check intervals
- Configure SSL/TLS

## Data Persistence

Data is stored in Docker volumes:
- `vmstorage-data` - Metrics data
- `vtstorage-data` - Traces data
- `vlstorage-data` - Logs data

### Backup Data

```bash
# Backup VictoriaMetrics
docker run --rm -v mirador-stack_vmstorage-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/vmstorage-backup.tar.gz /data

# Backup VictoriaTraces
docker run --rm -v mirador-stack_vtstorage-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/vtstorage-backup.tar.gz /data

# Backup VictoriaLogs
docker run --rm -v mirador-stack_vlstorage-data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/vlstorage-backup.tar.gz /data
```

## Monitoring

### Service Health

```bash
make health
```

### View Logs

```bash
# All services
make logs

# Specific component
make logs-gateway
make logs-vm
make logs-vt
make logs-vl
```

### HAProxy Stats

Access HAProxy statistics at `http://localhost:8404`
- Username: `admin`
- Password: `admin`

## Troubleshooting

### Services won't start

```bash
# Check logs
make logs

# Check container status
make status

# Verify configuration
docker compose config
```

### Network connectivity issues

```bash
# Test OTLP endpoint
make test

# Check network
docker network ls | grep mirador
docker network inspect mirador-stack_mirador
```

### Out of disk space

```bash
# Check volume usage
make volumes

# Clean unused resources
docker system prune -a
```

### Reset everything

```bash
# Stop and remove all data
make clean

# Start fresh
make up
```

## Performance Tuning

### Resource Limits

Edit `docker-compose.yaml` to add resource limits:

```yaml
services:
  vmstorage:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
```

### Batch Sizes

Adjust batch sizes in OTEL collector configs:

```yaml
processors:
  batch/metrics:
    timeout: 60s
    send_batch_size: 8192  # Increase for higher throughput
```

## Development

### Hot Reload Configuration

```bash
# Reload HAProxy config
docker compose exec haproxy kill -SIGUSR2 1

# Restart specific service
docker compose restart gateway
```

### Debug Mode

Enable debug logging:

```yaml
# In OTEL collector config
service:
  telemetry:
    logs:
      level: debug
```

## Architecture Decisions

### Why HAProxy?

- **Load Balancing**: Round-robin across multiple nodes
- **Health Checks**: Automatic failover for unhealthy backends
- **Statistics**: Built-in monitoring dashboard
- **Lightweight**: Minimal resource overhead

### Why Cluster Mode?

- **Scalability**: Horizontal scaling for high throughput
- **High Availability**: No single point of failure
- **Performance**: Distributed query and insert paths
- **Flexibility**: Scale insert and select independently

## Next Steps

1. **Add Authentication**: Configure mTLS or API keys
2. **Enable SSL/TLS**: Secure communication between nodes
3. **Set up Monitoring**: Deploy Prometheus + Grafana
4. **Configure Alerts**: Set up alerting for service health
5. **Optimize Resources**: Tune memory and CPU based on load

## Support

For issues and questions:
- GitHub Issues: [mirador-signals-pipeline](https://github.com/your-org/mirador-signals-pipeline)
- Documentation: See main README.md
