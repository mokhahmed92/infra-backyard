# Deployment Status - k3d-data-platform-cluster

## ✅ Completed

### 1. Cluster Verified
- Cluster: `k3d-data-platform-cluster` ✓
- Nodes: 3 (1 server, 2 agents) ✓
- ArgoCD: Installed ✓

### 2. Namespace Created
- `github-runners` namespace created ✓

### 3. GitHub App Credentials Secret Created
- Secret: `github-app-credentials` in `github-runners` namespace ✓
- App ID: `2067125` ✓
- Private Key: Configured ✓

### 4. ARC Controller Deployed
- Installed via official Helm chart (oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller:0.9.3) ✓
- Namespace: `arc-system` ✓
- Status: Running ✓

## ⏳ Pending

### 5. GitHub App Installation ID Required
To deploy the runner scale set, we need:

**Installation ID**: Find it here:
1. Go to your GitHub Organization Settings
2. Navigate to: Settings → GitHub Apps
3. Click on your app (`arc-runner-app-01`)
4. Click "Configure"
5. The URL will be: `https://github.com/organizations/YOUR_ORG/settings/installations/INSTALLATION_ID`
6. Copy the number from the URL

**Organization/Repository Scope**: Which one do you want?
- Organization-level: Provide organization name
- Repository-level: Provide repository (format: `org/repo`)

### 6. Deploy Runner Scale Set
Once Installation ID is provided, run:

```bash
# Update the secret with installation ID
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=github_app_id=2067125 \
  --from-literal=github_app_installation_id=YOUR_INSTALLATION_ID \
  --from-file=private-key="c:\Users\mokhtar\Downloads\arc-runner-app-01.2025-10-05.private-key.pem" \
  --dry-run=client -o yaml | kubectl apply -f -

# Install runner scale set
helm install arc-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace github-runners \
  --create-namespace \
  --set githubConfigUrl=https://github.com/YOUR_ORG \
  --set githubConfigSecret=github-app-credentials
```

## Current Resources

```bash
# Check controller
kubectl get pods -n arc-system
kubectl logs -n arc-system -l app.kubernetes.io/name=gha-rs-controller

# Check secrets
kubectl get secret github-app-credentials -n github-runners
```

## Next Steps

1. Find your GitHub App Installation ID
2. Update me with: Installation ID and Organization/Repository name
3. I'll deploy the runner scale set
4. We'll verify runners appear in GitHub
5. Test with a workflow
