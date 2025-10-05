# Manual Deployment Guide for k3d-data-platform-cluster

This guide walks you through manually deploying GitHub ARC to your local k3d cluster.

## Prerequisites

1. **k3d cluster running**: `k3d-data-platform-cluster` ✓
2. **ArgoCD installed**: ✓
3. **GitHub App configured** with credentials

## Step 1: Create GitHub App Credentials Secret

First, create the namespace:

```bash
kubectl create namespace github-runners
```

Create the secret with your GitHub App credentials:

```bash
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=github_app_id=YOUR_APP_ID \
  --from-literal=github_app_installation_id=YOUR_INSTALLATION_ID \
  --from-file=private-key=/path/to/your/private-key.pem
```

Replace:
- `YOUR_APP_ID` - Your GitHub App ID (e.g., 123456)
- `YOUR_INSTALLATION_ID` - Your GitHub App Installation ID (e.g., 12345678)
- `/path/to/your/private-key.pem` - Path to your downloaded private key

Verify the secret:

```bash
kubectl get secret github-app-credentials -n github-runners
kubectl describe secret github-app-credentials -n github-runners
```

## Step 2: Create Local ArgoCD Application for Controller

Since this is a local deployment, we'll use local file paths:

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: github-arc-controller
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    # For local deployment, you can use the local path
    repoURL: https://github.com/YOUR_USERNAME/infra-backyard.git
    targetRevision: main
    path: charts/github-arc-controller
    helm:
      releaseName: arc-controller

  destination:
    server: https://kubernetes.default.svc
    namespace: arc-system

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

**OR** use Helm directly for testing:

```bash
helm install arc-controller ./charts/github-arc-controller \
  --namespace arc-system \
  --create-namespace
```

Wait for controller to be ready:

```bash
kubectl wait --for=condition=Available deployment/arc-controller -n arc-system --timeout=300s
```

Check controller status:

```bash
kubectl get pods -n arc-system
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
```

## Step 3: Deploy ARC Runners

Create the runner scale set application:

```bash
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: github-arc-runners
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/YOUR_USERNAME/infra-backyard.git
    targetRevision: main
    path: charts/github-arc-runners
    helm:
      releaseName: arc-runners
      values: |
        github:
          auth:
            appID: "YOUR_APP_ID"
            installationID: "YOUR_INSTALLATION_ID"
            privateKey:
              secretName: "github-app-credentials"
              secretKey: "private-key"
          scope:
            organization: "YOUR_ORG"  # or use repository: "org/repo"

        runnerScaleSet:
          name: "arc-runners"
          namespace: "github-runners"
          minRunners: 0
          maxRunners: 5

  destination:
    server: https://kubernetes.default.svc
    namespace: github-runners

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

**OR** use Helm directly:

```bash
helm install arc-runners ./charts/github-arc-runners \
  --namespace github-runners \
  --create-namespace \
  --set github.auth.appID=YOUR_APP_ID \
  --set github.auth.installationID=YOUR_INSTALLATION_ID \
  --set github.scope.organization=YOUR_ORG
```

## Step 4: Verify Deployment

Check ArgoCD applications:

```bash
kubectl get applications -n argocd
```

Check all resources:

```bash
# Controller
kubectl get all -n arc-system

# Runners
kubectl get all -n github-runners

# AutoscalingRunnerSet
kubectl get autoscalingrunnerset -n github-runners
```

View logs:

```bash
# Controller logs
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller -f

# Listener logs (waits for jobs)
kubectl logs -n github-runners -l app.kubernetes.io/component=listener -f
```

## Step 5: Verify in GitHub

1. Go to your GitHub Organization Settings → Actions → Runners
2. You should see your runners listed (when jobs are queued, runners will appear)

## Step 6: Test with a Workflow

Create a test workflow in any repository in your organization:

```yaml
# .github/workflows/test-arc.yml
name: Test ARC Runners
on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, linux, x64]
    steps:
      - name: Test runner
        run: |
          echo "Running on ARC runner!"
          uname -a
          kubectl version --client
```

Trigger the workflow and watch the runner scale up:

```bash
# Watch runner pods
kubectl get pods -n github-runners -w
```

## Troubleshooting

### Runners not appearing

Check listener logs:
```bash
kubectl logs -n github-runners -l app.kubernetes.io/component=listener
```

Common issues:
- Wrong App ID or Installation ID
- GitHub App not installed to organization
- Missing permissions on GitHub App
- Private key format issue

### Controller issues

```bash
kubectl describe deployment arc-controller -n arc-system
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
```

### Check AutoscalingRunnerSet

```bash
kubectl describe autoscalingrunnerset arc-runners -n github-runners
```

## Cleanup

To remove everything:

```bash
# Delete ArgoCD applications
kubectl delete application github-arc-runners -n argocd
kubectl delete application github-arc-controller -n argocd

# Or delete directly
kubectl delete namespace github-runners
kubectl delete namespace arc-system
```

## Quick Commands Reference

```bash
# Status check
kubectl get applications -n argocd
kubectl get pods -n arc-system
kubectl get pods -n github-runners

# Logs
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller -f
kubectl logs -n github-runners -l app.kubernetes.io/component=listener -f

# Restart components
kubectl rollout restart deployment arc-controller -n arc-system
kubectl delete pod -n github-runners -l app.kubernetes.io/component=listener

# ArgoCD sync
kubectl get applications -n argocd
argocd app sync github-arc-controller
argocd app sync github-arc-runners
```
