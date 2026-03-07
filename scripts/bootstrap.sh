#!/usr/bin/env bash
set -euo pipefail

# Cassandra GitOps — One-time cluster bootstrap
# Installs ArgoCD + Image Updater, then applies the app-of-apps.
#
# Prerequisites:
#   - k3d cluster running (k3d cluster create cassandra)
#   - kubectl configured to point at the cluster
#   - GitHub PAT with read:packages scope (for pulling from GHCR)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Cassandra GitOps Bootstrap ==="
echo ""

# Check prerequisites
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: kubectl not connected to a cluster"
  echo "Run: k3d cluster create cassandra"
  exit 1
fi

CLUSTER=$(kubectl config current-context)
echo "Cluster: $CLUSTER"
echo ""

# 1. Install ArgoCD
echo "--- Installing ArgoCD ---"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "Waiting for ArgoCD to be ready..."
kubectl -n argocd wait --for=condition=available --timeout=120s deployment/argocd-server
echo "ArgoCD installed."
echo ""

# 2. Install ArgoCD Image Updater
echo "--- Installing ArgoCD Image Updater ---"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
echo "Waiting for Image Updater to be ready..."
kubectl -n argocd wait --for=condition=available --timeout=60s deployment/argocd-image-updater
echo "Image Updater installed."
echo ""

# 3. Configure GHCR credentials
echo "--- Configuring GHCR credentials ---"
if kubectl -n argocd get secret ghcr-credentials &>/dev/null; then
  echo "GHCR credentials already exist, skipping."
else
  echo "Create a GitHub PAT with read:packages scope."
  read -rp "GitHub username: " GH_USER
  read -rsp "GitHub PAT (read:packages): " GH_PAT
  echo ""
  kubectl -n argocd create secret generic ghcr-credentials \
    --from-literal=username="$GH_USER" \
    --from-literal=password="$GH_PAT"
  echo "GHCR credentials created."
fi
echo ""

# 4. Apply Image Updater registry config
echo "--- Applying Image Updater config ---"
kubectl apply -f "$REPO_DIR/argocd/image-updater.yaml"
# Restart image updater to pick up new config
kubectl -n argocd rollout restart deployment/argocd-image-updater
echo ""

# 5. Connect this gitops repo to ArgoCD
echo "--- Connecting gitops repo ---"
# For public repos, no credentials needed.
# For private repos, add a deploy key or PAT:
#   argocd repo add https://github.com/DigiBugCat/cassandra-k8s.git --username git --password <PAT>
echo "If the gitops repo is private, run:"
echo "  argocd repo add https://github.com/DigiBugCat/cassandra-k8s.git --username git --password <PAT>"
echo ""

# 6. Apply the app-of-apps (this bootstraps everything)
echo "--- Applying app-of-apps ---"
kubectl apply -f "$REPO_DIR/argocd/app-of-apps.yaml"
echo ""

# 7. Create application secrets (if not already present)
echo "--- Checking secrets ---"
kubectl create namespace claude-runner --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n claude-runner get secret claude-tokens &>/dev/null; then
  echo "Claude tokens secret not found."
  read -rsp "CLAUDE_CODE_OAUTH_TOKEN: " CLAUDE_TOKEN
  echo ""
  kubectl -n claude-runner create secret generic claude-tokens \
    --from-literal=CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_TOKEN"
  echo "Claude tokens secret created."
else
  echo "Claude tokens secret already exists."
fi
echo ""

# 8. Print status
echo "=== Bootstrap Complete ==="
echo ""
echo "ArgoCD UI:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8443:443"
echo "  https://localhost:8443"
echo ""
ADMIN_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not yet generated>")
echo "  Username: admin"
echo "  Password: $ADMIN_PASS"
echo ""
echo "Applications:"
kubectl -n argocd get applications 2>/dev/null || echo "  (syncing...)"
echo ""
echo "Grafana (after monitoring syncs):"
echo "  kubectl -n monitoring port-forward svc/grafana 3000:3000"
echo "  http://localhost:3000 (admin/admin)"
