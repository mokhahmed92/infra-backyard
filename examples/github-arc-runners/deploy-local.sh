#!/bin/bash
set -e

echo "=========================================="
echo "Deploying GitHub ARC to k3d-data-platform-cluster"
echo "=========================================="
echo ""

# Check if we're on the correct cluster
CURRENT_CONTEXT=$(kubectl config current-context)
if [ "$CURRENT_CONTEXT" != "k3d-data-platform-cluster" ]; then
    echo "❌ Error: Current context is '$CURRENT_CONTEXT'"
    echo "   Expected: 'k3d-data-platform-cluster'"
    echo ""
    echo "Switch context with:"
    echo "   kubectl config use-context k3d-data-platform-cluster"
    exit 1
fi

echo "✓ Connected to k3d-data-platform-cluster"
echo ""

# Verify ArgoCD is installed
echo "Checking ArgoCD installation..."
if ! kubectl get namespace argocd &>/dev/null; then
    echo "❌ ArgoCD namespace not found"
    echo "   Install ArgoCD first:"
    echo "   kubectl create namespace argocd"
    echo "   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    exit 1
fi

if ! kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server &>/dev/null; then
    echo "❌ ArgoCD not installed"
    exit 1
fi

echo "✓ ArgoCD is installed"
echo ""

# Check for GitHub App credentials
echo "Checking GitHub App credentials..."

# Prompt for credentials if not set
if [ -z "$GITHUB_APP_ID" ]; then
    read -p "Enter GitHub App ID: " GITHUB_APP_ID
fi

if [ -z "$GITHUB_APP_INSTALLATION_ID" ]; then
    read -p "Enter GitHub App Installation ID: " GITHUB_APP_INSTALLATION_ID
fi

if [ -z "$GITHUB_ORG" ]; then
    read -p "Enter GitHub Organization (or leave empty for repo/enterprise): " GITHUB_ORG
fi

if [ -z "$GITHUB_REPO" ] && [ -z "$GITHUB_ORG" ]; then
    read -p "Enter GitHub Repository (org/repo): " GITHUB_REPO
fi

if [ -z "$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
    read -p "Enter path to GitHub App private key (.pem file): " GITHUB_APP_PRIVATE_KEY_FILE
fi

# Validate private key file exists
if [ ! -f "$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
    echo "❌ Private key file not found: $GITHUB_APP_PRIVATE_KEY_FILE"
    exit 1
fi

echo "✓ Credentials provided"
echo ""

# Create github-runners namespace
echo "Creating github-runners namespace..."
kubectl create namespace github-runners --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Namespace created"
echo ""

# Create GitHub App credentials secret
echo "Creating GitHub App credentials secret..."
kubectl create secret generic github-app-credentials \
    --namespace=github-runners \
    --from-literal=github_app_id="$GITHUB_APP_ID" \
    --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
    --from-file=private-key="$GITHUB_APP_PRIVATE_KEY_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secret created"
echo ""

# Update ArgoCD applications with local repo path
echo "Deploying ArgoCD applications..."
echo ""

# Deploy controller first
echo "1. Deploying ARC Controller..."
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: github-arc-controller
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default

  source:
    repoURL: file:///$(pwd)
    targetRevision: HEAD
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
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

echo "   Waiting for controller to sync..."
sleep 5

# Wait for controller to be ready
echo "   Waiting for controller to be ready..."
kubectl wait --for=condition=Available deployment/arc-controller -n arc-system --timeout=300s || true

echo ""
echo "2. Deploying ARC Runners..."

# Determine GitHub scope
GITHUB_SCOPE_YAML=""
if [ -n "$GITHUB_ORG" ]; then
    GITHUB_SCOPE_YAML="organization: \"$GITHUB_ORG\""
elif [ -n "$GITHUB_REPO" ]; then
    GITHUB_SCOPE_YAML="repository: \"$GITHUB_REPO\""
fi

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: github-arc-runners
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  project: default

  source:
    repoURL: file:///$(pwd)
    targetRevision: HEAD
    path: charts/github-arc-runners
    helm:
      releaseName: arc-runners
      values: |
        github:
          auth:
            appID: "$GITHUB_APP_ID"
            installationID: "$GITHUB_APP_INSTALLATION_ID"
            privateKey:
              secretName: "github-app-credentials"
              secretKey: "private-key"
          scope:
            $GITHUB_SCOPE_YAML

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
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

echo ""
echo "=========================================="
echo "✓ Deployment initiated!"
echo "=========================================="
echo ""
echo "Check status:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -n arc-system"
echo "  kubectl get pods -n github-runners"
echo ""
echo "View logs:"
echo "  kubectl logs -n arc-system -l app.kubernetes.io/name=github-arc-controller -f"
echo "  kubectl logs -n github-runners -l app.kubernetes.io/component=listener -f"
echo ""
echo "ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Open: https://localhost:8080"
echo ""
