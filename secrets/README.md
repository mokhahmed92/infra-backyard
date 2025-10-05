# GitHub App Credentials Secret Management

This directory contains templates and examples for managing GitHub App credentials securely.

## Prerequisites

You need a GitHub App with the following permissions:

### Repository Permissions:
- **Actions**: Read & Write
- **Administration**: Read & Write
- **Checks**: Read
- **Metadata**: Read

### Organization Permissions:
- **Self-hosted runners**: Read & Write

## Secret Management Options

### Option 1: Manual Secret Creation (Development/Testing)

```bash
# Create the secret manually
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=github_app_id=YOUR_APP_ID \
  --from-literal=github_app_installation_id=YOUR_INSTALLATION_ID \
  --from-file=private-key=path/to/private-key.pem
```

**⚠️ Warning**: Do not use this in production or commit credentials to git.

### Option 2: Sealed Secrets (Recommended for GitOps)

1. Install Sealed Secrets controller:
```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

2. Install kubeseal CLI:
```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-linux-amd64 -O kubeseal
chmod +x kubeseal
sudo mv kubeseal /usr/local/bin/
```

3. Create and seal your secret:
```bash
# Fill in github-app-secret-template.yaml with real values
# Then seal it:
kubeseal --format=yaml < github-app-secret-template.yaml > github-app-sealed-secret.yaml

# Now you can safely commit github-app-sealed-secret.yaml to git
git add github-app-sealed-secret.yaml
git commit -m "Add sealed GitHub App credentials"
```

### Option 3: External Secrets Operator

1. Install External Secrets Operator:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets-system --create-namespace
```

2. Configure your secret backend (AWS Secrets Manager, Vault, etc.)

3. Apply the ExternalSecret manifest:
```bash
kubectl apply -f external-secret-example.yaml
```

### Option 4: ArgoCD Vault Plugin

If you're using ArgoCD with Vault Plugin:

1. Store secrets in HashiCorp Vault
2. Use AVP path substitution in your manifests
3. ArgoCD will inject secrets during deployment

## Getting GitHub App Credentials

1. **Create GitHub App**:
   - Go to GitHub Organization Settings → Developer settings → GitHub Apps
   - Click "New GitHub App"
   - Set Homepage URL and Webhook URL (can be placeholder)
   - Set required permissions (see above)
   - Click "Create GitHub App"

2. **Note the App ID**:
   - After creation, note the "App ID" (e.g., `123456`)

3. **Generate Private Key**:
   - Scroll to "Private keys" section
   - Click "Generate a private key"
   - Download the `.pem` file

4. **Install the App**:
   - Go to "Install App" tab
   - Install to your organization
   - Note the Installation ID from the URL (e.g., `https://github.com/organizations/YOUR_ORG/settings/installations/12345678`)

5. **Create the Secret**:
   - Use one of the methods above with your App ID, Installation ID, and private key

## Verification

After creating the secret, verify it exists:

```bash
kubectl get secret github-app-credentials -n github-runners
kubectl describe secret github-app-credentials -n github-runners
```

## Security Best Practices

- ✅ Use Sealed Secrets or External Secrets Operator in production
- ✅ Rotate GitHub App private keys regularly
- ✅ Use separate GitHub Apps for different environments (dev/staging/prod)
- ✅ Limit GitHub App permissions to minimum required
- ✅ Enable GitHub App webhook secret for additional security
- ❌ Never commit unencrypted secrets to git
- ❌ Never share private keys via insecure channels
