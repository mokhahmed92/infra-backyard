# GitHub Actions Runner Scale Set - Helm Chart

This Helm chart deploys a GitHub Actions Runner Scale Set with GitHub App authentication.

## Overview

This chart creates an AutoscalingRunnerSet that automatically scales GitHub Actions runners based on workflow queue depth. It uses GitHub App authentication for secure integration.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- GitHub Actions Runner Controller installed (see [github-arc-controller](../github-arc-controller/README.md))
- GitHub App configured with required permissions
- GitHub App credentials stored in Kubernetes secret

## GitHub App Setup

### Required Permissions

#### Repository Permissions:
- **Actions**: Read & Write
- **Administration**: Read & Write
- **Checks**: Read
- **Metadata**: Read

#### Organization Permissions:
- **Self-hosted runners**: Read & Write

### Create GitHub App

1. Go to GitHub Organization Settings → Developer settings → GitHub Apps
2. Click "New GitHub App"
3. Configure:
   - Name: `GitHub Actions Runner Controller`
   - Homepage URL: Your organization URL
   - Webhook: Uncheck "Active" (not needed)
4. Set permissions (see above)
5. Click "Create GitHub App"
6. Note the **App ID**
7. Generate a **private key** (download the .pem file)
8. Install the app to your organization
9. Note the **Installation ID** from the URL

### Create Credentials Secret

```bash
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=github_app_id=YOUR_APP_ID \
  --from-literal=github_app_installation_id=YOUR_INSTALLATION_ID \
  --from-file=private-key=path/to/private-key.pem
```

For production, use [Sealed Secrets](../../secrets/README.md) or External Secrets Operator.

## Installation

### Organization-Level Runners

```bash
helm install arc-runners ./charts/github-arc-runners \
  --namespace github-runners \
  --create-namespace \
  --set github.auth.appID=YOUR_APP_ID \
  --set github.auth.installationID=YOUR_INSTALLATION_ID \
  --set github.scope.organization=YOUR_ORG
```

### Repository-Level Runners

```bash
helm install arc-runners ./charts/github-arc-runners \
  --namespace github-runners \
  --create-namespace \
  --set github.auth.appID=YOUR_APP_ID \
  --set github.auth.installationID=YOUR_INSTALLATION_ID \
  --set github.scope.repository=YOUR_ORG/YOUR_REPO
```

### Enterprise-Level Runners

```bash
helm install arc-runners ./charts/github-arc-runners \
  --namespace github-runners \
  --create-namespace \
  --set github.auth.appID=YOUR_APP_ID \
  --set github.auth.installationID=YOUR_INSTALLATION_ID \
  --set github.scope.enterprise=YOUR_ENTERPRISE
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `github.auth.appID` | GitHub App ID | `""` (required) |
| `github.auth.installationID` | GitHub App Installation ID | `""` (required) |
| `github.auth.privateKey.secretName` | Secret containing private key | `github-app-credentials` |
| `github.auth.privateKey.secretKey` | Key in secret | `private-key` |
| `github.scope.organization` | Organization name | `""` |
| `github.scope.repository` | Repository (org/repo) | `""` |
| `github.scope.enterprise` | Enterprise name | `""` |
| `github.runnerGroup` | Runner group | `Default` |
| `runnerScaleSet.name` | Scale set name | `arc-runners` |
| `runnerScaleSet.namespace` | Namespace for runners | `github-runners` |
| `runnerScaleSet.minRunners` | Minimum idle runners | `0` |
| `runnerScaleSet.maxRunners` | Maximum runners | `10` |
| `runnerScaleSet.labels` | Runner labels | `[self-hosted, linux, x64]` |

### Example Custom Values

```yaml
github:
  auth:
    appID: "123456"
    installationID: "12345678"
  scope:
    organization: "my-org"
  runnerGroup: "Production"

runnerScaleSet:
  name: "production-runners"
  minRunners: 2
  maxRunners: 20
  labels:
    - "self-hosted"
    - "linux"
    - "x64"
    - "production"

  template:
    spec:
      containers:
        - name: runner
          image: ghcr.io/actions/actions-runner:latest
          resources:
            requests:
              cpu: "1000m"
              memory: "2Gi"
            limits:
              cpu: "4000m"
              memory: "8Gi"

      nodeSelector:
        workload-type: github-runners
```

## Using Runners in Workflows

Target your runners using the labels defined in the chart:

```yaml
name: CI
on: [push]

jobs:
  build:
    runs-on: [self-hosted, linux, x64]
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on ARC runner!"
```

## Scaling Behavior

The runner scale set automatically scales based on:

- **Queue depth**: Number of pending workflow jobs
- **Min/Max runners**: Configured limits
- **Ephemeral runners**: Each job gets a fresh runner

### Scaling Example

```
Pending Jobs: 5
Min Runners: 0
Max Runners: 10
Current Runners: 0

Result: Scale up to 5 runners

After jobs complete:
Active Jobs: 0
Current Runners: 5

Result: Scale down to 0 (min) after cooldown
```

## Monitoring

### Check Runner Registration

```bash
# View AutoscalingRunnerSet
kubectl get autoscalingrunnerset -n github-runners

# Check runner pods
kubectl get pods -n github-runners

# View listener logs
kubectl logs -n github-runners -l app.kubernetes.io/component=listener
```

### Verify in GitHub

1. Go to your GitHub Organization/Repository Settings
2. Navigate to Actions → Runners
3. You should see your registered runners

## Troubleshooting

### Runners Not Appearing in GitHub

1. Check listener logs:
```bash
kubectl logs -n github-runners -l app.kubernetes.io/component=listener
```

2. Verify credentials secret:
```bash
kubectl get secret github-app-credentials -n github-runners
kubectl describe secret github-app-credentials -n github-runners
```

3. Check GitHub App installation:
   - Verify App ID and Installation ID are correct
   - Ensure the app is installed to the correct organization/repository
   - Check app permissions

### Authentication Errors

```bash
# Check for auth errors in listener logs
kubectl logs -n github-runners -l app.kubernetes.io/component=listener | grep -i auth

# Verify secret contents (base64 encoded)
kubectl get secret github-app-credentials -n github-runners -o yaml
```

### Runners Not Scaling

1. Check AutoscalingRunnerSet status:
```bash
kubectl describe autoscalingrunnerset arc-runners -n github-runners
```

2. Verify controller is running:
```bash
kubectl get pods -n arc-system
```

3. Check controller logs:
```bash
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
```

### High Resource Usage

Adjust runner resources:

```bash
helm upgrade arc-runners ./charts/github-arc-runners \
  --namespace github-runners \
  --set runnerScaleSet.template.spec.containers[0].resources.limits.cpu=2000m \
  --set runnerScaleSet.template.spec.containers[0].resources.limits.memory=4Gi
```

## Custom Runner Images

### Using a Custom Image

```yaml
runnerScaleSet:
  template:
    spec:
      containers:
        - name: runner
          image: myregistry.io/my-custom-runner:latest
          imagePullPolicy: Always
```

### Building Custom Images

Create a Dockerfile based on the official runner:

```dockerfile
FROM ghcr.io/actions/actions-runner:latest

USER root

# Install additional tools
RUN apt-get update && apt-get install -y \
    docker.io \
    kubectl \
    && rm -rf /var/lib/apt/lists/*

USER runner
```

## Security Best Practices

- ✅ Use GitHub App authentication (more secure than PAT)
- ✅ Limit GitHub App permissions to minimum required
- ✅ Use Sealed Secrets or External Secrets for credentials
- ✅ Run runners as non-root user
- ✅ Use ephemeral runners (default)
- ✅ Implement network policies
- ✅ Regularly rotate GitHub App private keys
- ✅ Use separate runner scale sets for different security contexts

## Uninstallation

```bash
helm uninstall arc-runners --namespace github-runners

# Optional: Remove namespace and secrets
kubectl delete namespace github-runners
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│            AutoscalingRunnerSet                 │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  Listener Pod                            │  │
│  │  - Monitors GitHub workflow queue        │  │
│  │  - Requests scaling via controller       │  │
│  └──────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │  Runner Pods (0-N)                       │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐        │  │
│  │  │Runner 1│ │Runner 2│ │Runner N│        │  │
│  │  └────────┘ └────────┘ └────────┘        │  │
│  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

## Next Steps

1. Create a test workflow to verify runner functionality
2. Configure scaling parameters based on your workload
3. Set up monitoring and alerts
4. Consider creating multiple scale sets for different use cases
5. Implement resource quotas and limits

## Links

- [Actions Runner Controller Docs](https://github.com/actions/actions-runner-controller)
- [GitHub Apps Authentication](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app)
- [GitHub Actions Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
