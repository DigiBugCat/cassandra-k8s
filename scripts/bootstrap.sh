#!/usr/bin/env bash
set -euo pipefail

# Cassandra k8s — One-time cluster bootstrap
# Installs ArgoCD, Image Updater, Sealed Secrets, then applies the app-of-apps.
#
# Prerequisites:
#   - k3d cluster running (k3d cluster create cassandra)
#   - kubectl configured to point at the cluster
#   - GitHub PAT with read:packages scope (for pulling from GHCR)
#   - kubeseal CLI installed (brew install kubeseal)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Cassandra k8s Bootstrap ==="
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
# Poll git every 30s instead of default 3min — faster deploys
# Enable OCI Helm support for ARC charts from ghcr.io
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"30s","helm.enabled":"true"}}'
echo "ArgoCD installed (30s reconciliation interval, OCI Helm enabled)."
echo ""

# 2. Install ArgoCD Image Updater
echo "--- Installing ArgoCD Image Updater ---"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
echo "Waiting for Image Updater to be ready..."
kubectl -n argocd wait --for=condition=available --timeout=60s deployment/argocd-image-updater
# Poll GHCR every 30s instead of default 2min — faster deploys
kubectl -n argocd patch deploy argocd-image-updater --type=json \
  -p '[{"op":"replace","path":"/spec/template/spec/containers/0/args","value":["run","--interval","30s"]}]'
echo "Image Updater installed (30s poll interval)."
echo ""

# 3. Install Sealed Secrets controller
echo "--- Installing Sealed Secrets ---"
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.3/controller.yaml
echo "Waiting for Sealed Secrets controller..."
kubectl -n kube-system wait --for=condition=available --timeout=60s deployment/sealed-secrets-controller
echo "Sealed Secrets installed."
echo ""

# 4. Configure GHCR credentials
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

# 5. Apply Image Updater registry config
echo "--- Applying Image Updater config ---"
kubectl apply -f "$REPO_DIR/argocd/image-updater.yaml"
kubectl -n argocd rollout restart deployment/argocd-image-updater
echo ""

# 6. Connect this repo to ArgoCD
echo "--- Connecting k8s repo ---"
echo "If the repo is private, run:"
echo "  argocd repo add https://github.com/DigiBugCat/cassandra-k8s.git --username git --password <PAT>"
echo ""

# 7. Apply the app-of-apps
echo "--- Applying app-of-apps ---"
kubectl apply -f "$REPO_DIR/argocd/app-of-apps.yaml"
echo ""

# 8. Print status and next steps
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
echo "=== Next: Seal your secrets ==="
echo ""
echo "Secrets are managed via Sealed Secrets. To create encrypted values:"
echo ""
echo "  # 1. Seal a secret value for production (namespace: claude-runner)"
echo "  echo -n 'sk-ant-oat-...' | kubeseal --raw --namespace claude-runner --name claude-tokens --from-file=/dev/stdin"
echo ""
echo "  # 2. Seal a secret value for dev (namespace: claude-runner-dev)"
echo "  echo -n 'sk-ant-oat-...' | kubeseal --raw --namespace claude-runner-dev --name claude-tokens --from-file=/dev/stdin"
echo ""
echo "  # 3. Paste the output into values-production.yaml or values-dev.yaml under sealedSecrets:"
echo "  #    sealedSecrets:"
echo "  #      claudeTokens:"
echo "  #        CLAUDE_CODE_OAUTH_TOKEN: \"AgBy3i4OJSWK+...\""
echo ""
echo "  # 4. Commit and push — ArgoCD applies the SealedSecret, controller decrypts it."
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
