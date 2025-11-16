# Mirador Signals Pipeline - Deployment Guide

> **Note**: This directory contains the base OpenTelemetry Collector Helm chart used by Mirador Pipelines.
> 
> **For complete deployment instructions, see:** `../mirador-pipelines/README.md`

## Quick Reference

The Mirador Signals Pipeline uses an **umbrella chart** approach. This base chart (`uat-pipeline/`) is deployed four times with different configurations to create the complete pipeline.

### Single Command Deployment

```bash
cd ../mirador-pipelines
helm dependency update
helm install mirador-pipelines . --namespace observability
```

This deploys all four collectors:
1. Gateway (3 replicas) - with load balancing exporters
2. Service Graph (1 replica)
3. Span Metrics (1 replica)
4. Isolation Forest (1 replica)

## Architecture

See `../mirador-pipelines/README.md` for complete architecture diagrams and component descriptions.

## About This Chart

This is the **base chart** that provides the OpenTelemetry Collector deployment capabilities. The umbrella chart (`mirador-pipelines/`) uses this chart four times with different `values.yaml` configurations to create the complete pipeline stack.

## Full Documentation

- **Deployment Guide**: `../mirador-pipelines/README.md`
- **Configuration Examples**: See umbrella chart values.yaml
- **Troubleshooting**: See umbrella chart README
- **OTelBin Configs**: `../otelbin-configs/`
