# ArgoCD Applications for GitHub Actions Runner Controller

This directory contains ArgoCD Application manifests for deploying GitHub Actions Runner Controller (ARC) and runner scale sets.

## Structure

```
argocd/
├── apps/
│   ├── github-arc-controller.yaml    # Controller application
│   ├── github-arc-runners.yaml       # Runner scale set application
│   ├── app-of-apps.yaml              # App-of-apps pattern (optional)
│   └── kustomization.yaml            # Kustomize wrapper
└── README.md
```

## Deployment Options

### Option 1: Deploy Individual Apps

Deploy the controller first, then the runners:

```bash
# Deploy controller
kubectl apply -f argocd/apps/github-arc-controller.yaml

# Wait for controller to be ready
kubectl wait --for=condition=Available deployment/arc-controller -n arc-system --timeout=300s

# Deploy runners
kubectl apply -f argocd/apps/github-arc-runners.yaml
```

### Option 2: Deploy Using App-of-Apps Pattern

Deploy both applications at once using the app-of-apps pattern:

```bash
kubectl apply -f argocd/apps/app-of-apps.yaml
```

This will automatically deploy both the controller and runners with proper ordering.

### Option 3: Deploy Using Kustomize

```bash
kubectl apply -k argocd/apps/
```

## Configuration

### Before Deploying

1. **Update Repository URL**: Edit the `repoURL` fields in the Application manifests to point to your git repository.

2. **Configure GitHub App Credentials**:
   - Update `github.auth.appID` in `github-arc-runners.yaml`
   - Update `github.auth.installationID` in `github-arc-runners.yaml`
   - Ensure the secret `github-app-credentials` exists in the `github-runners` namespace

3. **Set GitHub Scope**:
   - For organization-level runners: Set `github.scope.organization`
   - For repository-level runners: Set `github.scope.repository`
   - For enterprise-level runners: Set `github.scope.enterprise`

### Customization

You can override values using ArgoCD:

#### Via ArgoCD UI:
1. Go to the Application in ArgoCD UI
2. Click "App Details" → "Parameters"
3. Edit values

#### Via CLI:
```bash
argocd app set github-arc-runners \
  --helm-set github.auth.appID=123456 \
  --helm-set github.auth.installationID=12345678 \
  --helm-set github.scope.organization=my-org
```

#### Via values file:
Edit the `values:` section in the Application manifest directly.

## Sync Waves

Applications use sync waves to ensure proper deployment order:

- **Wave 1**: Controller (must be deployed first)
- **Wave 2**: Runners (deployed after controller is ready)

This ensures the CRDs and controller are available before deploying runner scale sets.

## Sync Policies

Both applications are configured with:

- **Auto-sync**: Automatically sync when changes are detected
- **Self-heal**: Automatically revert manual changes to match git
- **Prune**: Remove resources that are no longer in git
- **Retry**: Automatically retry failed syncs with exponential backoff

### Manual Sync

To disable auto-sync and sync manually:

```bash
# Disable auto-sync
argocd app set github-arc-controller --sync-policy none

# Manual sync
argocd app sync github-arc-controller
argocd app sync github-arc-runners
```

## Monitoring

### Check Application Status

```bash
# Via ArgoCD CLI
argocd app get github-arc-controller
argocd app get github-arc-runners

# Via kubectl
kubectl get applications -n argocd
```

### Check Sync Status

```bash
argocd app list
argocd app wait github-arc-controller --health
argocd app wait github-arc-runners --health
```

### View Logs

```bash
# Controller logs
kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller -f

# Listener logs
kubectl logs -n github-runners -l app.kubernetes.io/component=listener -f

# Runner logs
kubectl logs -n github-runners -l app.kubernetes.io/name=github-arc-runners -f
```

## Troubleshooting

### Application Won't Sync

1. Check ArgoCD application status:
   ```bash
   argocd app get github-arc-controller
   ```

2. Check for sync errors:
   ```bash
   kubectl describe application github-arc-controller -n argocd
   ```

3. Manually trigger sync:
   ```bash
   argocd app sync github-arc-controller --force
   ```

### Controller Not Starting

1. Check deployment status:
   ```bash
   kubectl get deployment -n arc-system
   kubectl describe deployment arc-controller -n arc-system
   ```

2. Check pod logs:
   ```bash
   kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller
   ```

### Runners Not Registering

1. Verify GitHub App credentials secret exists:
   ```bash
   kubectl get secret github-app-credentials -n github-runners
   ```

2. Check listener logs for authentication errors:
   ```bash
   kubectl logs -n github-runners -l app.kubernetes.io/component=listener
   ```

3. Verify AutoscalingRunnerSet:
   ```bash
   kubectl get autoscalingrunnerset -n github-runners
   kubectl describe autoscalingrunnerset arc-runners -n github-runners
   ```

### Diff Shows Changes But Won't Sync

This might be due to ignored differences. Check the `ignoreDifferences` section in the Application manifest.

## Cleanup

### Remove Applications

```bash
# Using ArgoCD
argocd app delete github-arc-runners
argocd app delete github-arc-controller

# Or using kubectl
kubectl delete -f argocd/apps/github-arc-runners.yaml
kubectl delete -f argocd/apps/github-arc-controller.yaml
```

### Remove App-of-Apps

```bash
kubectl delete -f argocd/apps/app-of-apps.yaml
```

### Complete Cleanup

```bash
# Delete all resources
kubectl delete namespace arc-system
kubectl delete namespace github-runners
kubectl delete clusterrole arc-controller
kubectl delete clusterrolebinding arc-controller
```

## Security Considerations

- ✅ Controller runs with minimal RBAC permissions
- ✅ Runners run as non-root user
- ✅ Secrets are mounted read-only
- ✅ GitHub App credentials stored in Kubernetes secrets
- ⚠️ Consider using Sealed Secrets or External Secrets for secret management
- ⚠️ Regularly rotate GitHub App private keys

## Next Steps

1. Configure GitHub App and create credentials secret
2. Update Application manifests with your configuration
3. Deploy using one of the methods above
4. Test with a sample GitHub Actions workflow
5. Configure scaling parameters based on your needs
6. Set up monitoring and alerting
