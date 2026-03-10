#!/usr/bin/env bash
set -euo pipefail

# Cassandra k8s — One-time cluster bootstrap
# Installs ArgoCD, then applies the app-of-apps.
#
# Prerequisites:
#   - k3s cluster running
#   - kubectl configured to point at the cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Cassandra k8s Bootstrap ==="
echo ""

# Check prerequisites
if ! kubectl cluster-info &>/dev/null; then
  echo "ERROR: kubectl not connected to a cluster"
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
# Poll git every 30s instead of default 3min — faster deploys
# Enable OCI Helm support for ARC charts
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"30s","helm.enabled":"true"}}'
echo "ArgoCD installed (30s reconciliation interval, OCI Helm enabled)."
echo ""

# 2. Connect this repo to ArgoCD
echo "--- Connecting k8s repo ---"
echo "If the repo is private, run:"
echo "  argocd repo add https://github.com/DigiBugCat/cassandra-k8s.git --username git --password <PAT>"
echo ""

# 3. Apply the app-of-apps
echo "--- Applying app-of-apps ---"
kubectl apply -f "$REPO_DIR/argocd/app-of-apps.yaml"
echo ""

# 4. Print status and next steps
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
echo "=== Next: Create secrets ==="
echo ""
echo "All secrets are managed manually via kubectl. See docs/setup.md for the full list."
echo ""
echo "  kubectl create secret generic claude-tokens --namespace claude-runner \\"
echo "    --from-literal=CLAUDE_CODE_OAUTH_TOKEN='sk-ant-...'"
echo ""
echo "=== GitHub Actions Runners (ARC) ==="
echo ""
echo "Self-hosted runners are managed by ARC (Actions Runner Controller)."
echo "The controller and runner scale set are deployed via ArgoCD."
echo ""
echo "To configure auth:"
echo "  1. Create a fine-grained PAT at https://github.com/settings/personal-access-tokens/new"
echo "     - Resource owner: DigiBugCat"
echo "     - Repository access: All repositories"
echo "     - Permissions: Administration → Read & Write (for self-hosted runners)"
echo "  2. Create the secret on the cluster:"
echo "     kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -"
echo "     kubectl create secret generic github-secret --namespace arc-runners --from-literal=github_token='ghp_...'"
echo "  3. Use 'runs-on: arc-runner' in GitHub Actions workflows"
echo ""
echo "Grafana (after monitoring syncs):"
echo "  kubectl -n monitoring port-forward svc/grafana 3000:3000"
echo "  http://localhost:3000 (admin/admin)"
