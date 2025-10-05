# GitHub Actions Runner Controller (ARC) - Helm Chart

This Helm chart deploys the GitHub Actions Runner Controller for Kubernetes.

## Overview

The GitHub Actions Runner Controller manages the lifecycle of self-hosted GitHub Actions runners in Kubernetes. It works in conjunction with runner scale sets to automatically scale runners based on workflow demand.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- GitHub App configured with appropriate permissions

## Installation

### Basic Installation

```bash
helm install arc-controller ./charts/github-arc-controller \
  --namespace arc-system \
  --create-namespace
```

### With Custom Values

```bash
helm install arc-controller ./charts/github-arc-controller \
  --namespace arc-system \
  --create-namespace \
  --values custom-values.yaml
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of controller replicas | `1` |
| `image.repository` | Controller image repository | `ghcr.io/actions/gha-runner-scale-set-controller` |
| `image.tag` | Controller image tag | `0.9.3` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `serviceAccount.create` | Create service account | `true` |
| `serviceAccount.name` | Service account name | `arc-controller-sa` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `controller.logLevel` | Log level (debug, info, warn, error) | `info` |
| `controller.logFormat` | Log format (json, text) | `json` |
| `controller.watchNamespace` | Namespace to watch (empty = all) | `""` |
| `controller.metrics.enabled` | Enable metrics endpoint | `true` |
| `controller.metrics.port` | Metrics port | `8080` |

### Example Custom Values

```yaml
replicaCount: 2

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi

controller:
  logLevel: debug
  watchNamespace: "github-runners"

metricsService:
  enabled: true
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"

nodeSelector:
  node-role.kubernetes.io/control-plane: ""

tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

## Uninstallation

```bash
helm uninstall arc-controller --namespace arc-system
```

## Monitoring

The controller exposes Prometheus metrics on port 8080 at `/metrics`:

```bash
# Port-forward to access metrics locally
kubectl port-forward -n arc-system svc/arc-controller-metrics 8080:8080

# Access metrics
curl http://localhost:8080/metrics
```

## Troubleshooting

### Controller Not Starting

Check pod status and logs:

```bash
kubectl get pods -n arc-system
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
```

### Permission Errors

Verify RBAC is configured correctly:

```bash
kubectl get clusterrole arc-controller
kubectl get clusterrolebinding arc-controller
kubectl auth can-i create autoscalingrunnerset --as=system:serviceaccount:arc-system:arc-controller-sa
```

### High Memory Usage

Increase memory limits:

```bash
helm upgrade arc-controller ./charts/github-arc-controller \
  --namespace arc-system \
  --set resources.limits.memory=1Gi
```

## Architecture

```
┌─────────────────────────────────────┐
│   GitHub Actions Runner Controller  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │   Controller Manager         │  │
│  │   - Watches AutoscalingRS    │  │
│  │   - Manages Runner Lifecycle │  │
│  │   - Handles Scaling Logic    │  │
│  └──────────────────────────────┘  │
│                                     │
│  ┌──────────────────────────────┐  │
│  │   Metrics Server             │  │
│  │   - Prometheus metrics       │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Next Steps

After installing the controller:

1. Install runner scale sets: See [github-arc-runners chart](../github-arc-runners/README.md)
2. Configure GitHub App credentials
3. Create AutoscalingRunnerSet resources
4. Test with a GitHub Actions workflow

## Links

- [GitHub Actions Runner Controller Documentation](https://github.com/actions/actions-runner-controller)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
