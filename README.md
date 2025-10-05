# Infrastructure Backyard

Infrastructure as Code repository for GitHub Actions Runner Controller (ARC) with ArgoCD GitOps deployment.

## Overview

This repository contains Helm charts and ArgoCD applications for deploying GitHub Actions self-hosted runners on Kubernetes using the Actions Runner Controller (ARC) with GitHub App authentication.

## Repository Structure

```
.
├── charts/
│   ├── github-arc-controller/     # ARC controller Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── templates/
│   │   └── README.md
│   │
│   └── github-arc-runners/        # Runner scale set Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       └── README.md
│
├── argocd/
│   ├── apps/                      # ArgoCD Application manifests
│   │   ├── github-arc-controller.yaml
│   │   ├── github-arc-runners.yaml
│   │   ├── app-of-apps.yaml
│   │   └── kustomization.yaml
│   └── README.md
│
├── secrets/                       # Secret management templates
│   ├── github-app-secret-template.yaml
│   ├── sealed-secret-example.yaml
│   ├── external-secret-example.yaml
│   └── README.md
│
└── README.md
```

## Quick Start

### Prerequisites

1. **Kubernetes Cluster** (v1.23+)
2. **ArgoCD** installed in the cluster
3. **GitHub App** configured with required permissions
4. **Helm** (v3.8+) for local testing

### Step 1: Create GitHub App

1. Navigate to your GitHub Organization Settings → Developer settings → GitHub Apps
2. Click "New GitHub App" and configure:
   - **Name**: GitHub Actions Runner Controller
   - **Homepage URL**: Your organization URL
   - **Webhook**: Uncheck "Active"

3. Set the following **permissions**:
   - Repository: Actions (R/W), Administration (R/W), Checks (R), Metadata (R)
   - Organization: Self-hosted runners (R/W)

4. Create the app and note:
   - **App ID**
   - **Installation ID** (from installation URL)
   - **Private Key** (generate and download)

See [detailed instructions](secrets/README.md).

### Step 2: Create Credentials Secret

Choose one of the following methods:

#### Option A: Manual (Development)

```bash
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=github_app_id=YOUR_APP_ID \
  --from-literal=github_app_installation_id=YOUR_INSTALLATION_ID \
  --from-file=private-key=path/to/private-key.pem
```

#### Option B: Sealed Secrets (Recommended)

```bash
# Install Sealed Secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Create and seal the secret
kubeseal --format=yaml < secrets/github-app-secret-template.yaml > github-app-sealed-secret.yaml
kubectl apply -f github-app-sealed-secret.yaml
```

See [secrets documentation](secrets/README.md) for more options.

### Step 3: Configure ArgoCD Applications

Update the ArgoCD application manifests with your configuration:

```bash
# Edit controller application
vim argocd/apps/github-arc-controller.yaml

# Update repository URL
# No other changes needed for controller

# Edit runners application
vim argocd/apps/github-arc-runners.yaml

# Update:
# - Repository URL
# - github.auth.appID
# - github.auth.installationID
# - github.scope.organization (or repository/enterprise)
```

### Step 4: Deploy with ArgoCD

#### Option A: Individual Apps

```bash
# Deploy controller
kubectl apply -f argocd/apps/github-arc-controller.yaml

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/arc-controller -n arc-system --timeout=300s

# Deploy runners
kubectl apply -f argocd/apps/github-arc-runners.yaml
```

#### Option B: App-of-Apps (Recommended)

```bash
# Deploy both at once
kubectl apply -f argocd/apps/app-of-apps.yaml
```

### Step 5: Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check controller
kubectl get pods -n arc-system
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller

# Check runners
kubectl get autoscalingrunnerset -n github-runners
kubectl get pods -n github-runners

# Verify in GitHub UI
# Go to Organization Settings → Actions → Runners
# You should see your runners registered
```

### Step 6: Test with a Workflow

Create a test workflow in your repository:

```yaml
# .github/workflows/test-runner.yml
name: Test Self-Hosted Runner
on: [push]

jobs:
  test:
    runs-on: [self-hosted, linux, x64]
    steps:
      - uses: actions/checkout@v4
      - name: Echo test
        run: |
          echo "Running on self-hosted runner!"
          uname -a
```

## Configuration

### Controller Configuration

The controller can be configured via [charts/github-arc-controller/values.yaml](charts/github-arc-controller/values.yaml):

- Resource limits/requests
- Log level and format
- Metrics configuration
- Namespace watching scope

### Runner Configuration

Runners can be configured via [charts/github-arc-runners/values.yaml](charts/github-arc-runners/values.yaml):

- GitHub scope (organization/repository/enterprise)
- Min/max runners
- Runner labels
- Resource limits
- Custom runner images
- Node selectors and tolerations

See the [runner chart README](charts/github-arc-runners/README.md) for details.

## Monitoring

### Prometheus Metrics

The controller exposes metrics on port 8080:

```bash
kubectl port-forward -n arc-system svc/arc-controller-metrics 8080:8080
curl http://localhost:8080/metrics
```

### Logs

```bash
# Controller logs
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller -f

# Listener logs
kubectl logs -n github-runners -l app.kubernetes.io/component=listener -f

# Runner logs
kubectl logs -n github-runners -l app.kubernetes.io/name=github-arc-runners -f
```

### ArgoCD Dashboard

Access the ArgoCD UI to view application status:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

## Scaling

Runners automatically scale based on workflow queue depth:

- **Scale up**: When workflows are queued
- **Scale down**: When runners are idle (respects minRunners)
- **Ephemeral**: Each job gets a fresh runner

Configure scaling in `values.yaml`:

```yaml
runnerScaleSet:
  minRunners: 0
  maxRunners: 10
```

## Troubleshooting

### Runners Not Registering

1. Check GitHub App credentials:
   ```bash
   kubectl get secret github-app-credentials -n github-runners
   ```

2. Check listener logs:
   ```bash
   kubectl logs -n github-runners -l app.kubernetes.io/component=listener
   ```

3. Verify GitHub App permissions and installation

### Controller Issues

1. Check controller status:
   ```bash
   kubectl get deployment -n arc-system
   kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
   ```

2. Verify RBAC:
   ```bash
   kubectl get clusterrole arc-controller
   kubectl get clusterrolebinding arc-controller
   ```

### ArgoCD Sync Issues

1. Check application status:
   ```bash
   argocd app get github-arc-controller
   argocd app get github-arc-runners
   ```

2. Force sync:
   ```bash
   argocd app sync github-arc-controller --force
   ```

See [troubleshooting guides](argocd/README.md) for more details.

## Security

### Best Practices

- ✅ Use GitHub App authentication (not PAT)
- ✅ Implement Sealed Secrets or External Secrets
- ✅ Run runners as non-root
- ✅ Use ephemeral runners
- ✅ Limit GitHub App permissions
- ✅ Regularly rotate credentials
- ✅ Implement network policies
- ✅ Use RBAC effectively

### Secret Management

This repository supports multiple secret management solutions:

- **Sealed Secrets** - Encrypt secrets for Git storage
- **External Secrets Operator** - Sync from external vaults
- **ArgoCD Vault Plugin** - Inject secrets during deployment

See [secrets documentation](secrets/README.md) for implementation guides.

## Maintenance

### Upgrading

Update image tags in `values.yaml` and sync:

```bash
# Update controller version
helm upgrade arc-controller ./charts/github-arc-controller \
  --namespace arc-system \
  --set image.tag=0.10.0

# Or via ArgoCD
argocd app sync github-arc-controller
```

### Backup

Backup important resources:

```bash
kubectl get autoscalingrunnerset -n github-runners -o yaml > backup-runners.yaml
kubectl get secret github-app-credentials -n github-runners -o yaml > backup-secret.yaml
```

## Contributing

1. Create a feature branch
2. Make changes to charts or manifests
3. Test locally with Helm
4. Update documentation
5. Submit pull request

## Documentation

- [Controller Chart](charts/github-arc-controller/README.md)
- [Runner Chart](charts/github-arc-runners/README.md)
- [ArgoCD Apps](argocd/README.md)
- [Secret Management](secrets/README.md)

## External Links

- [GitHub Actions Runner Controller](https://github.com/actions/actions-runner-controller)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)

## License

See [LICENSE](LICENSE) file for details.