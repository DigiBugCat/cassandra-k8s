# Cassandra GitOps — Setup Guide

## Prerequisites

- **k3d** installed (`brew install k3d` or from https://k3d.io)
- **kubectl** installed and configured
- **GitHub PAT** with `read:packages` scope (for pulling images from GHCR)
- **CLAUDE_CODE_OAUTH_TOKEN** (from Anthropic)

## Initial Setup

### 1. Create the k3d cluster

```bash
k3d cluster create cassandra \
  --port "9080:9080@server:0" \
  --port "9081:9081@server:0" \
  --port "3000:3000@server:0"
```

Port mappings:
- `9080` — Claude Runner API
- `9081` — Claude Runner WebSocket (internal)
- `3000` — Grafana

### 2. Create a GHCR pull secret

k3d nodes need to pull images from GHCR. Create a `registries.yaml`:

```yaml
# ~/.k3d/registries.yaml
mirrors:
  ghcr.io:
    endpoint:
      - https://ghcr.io
configs:
  ghcr.io:
    auth:
      username: <github-username>
      password: <github-pat-with-read:packages>
```

Then create the cluster with:
```bash
k3d cluster create cassandra \
  --port "9080:9080@server:0" \
  --port "9081:9081@server:0" \
  --port "3000:3000@server:0" \
  --registry-config ~/.k3d/registries.yaml
```

### 3. Bootstrap ArgoCD

```bash
./scripts/bootstrap.sh
```

This installs:
- ArgoCD (watches this repo for manifest changes)
- ArgoCD Image Updater (watches GHCR for new image tags)
- Configures GHCR credentials
- Applies the app-of-apps (which creates all Application CRDs)
- Creates the `claude-tokens` secret

### 4. Verify

```bash
# Check applications
kubectl -n argocd get applications

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8443:443
# Open https://localhost:8443
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## How Deployments Work

### Code changes (claude-agent-runner repo)

1. Push to `main` in `claude-agent-runner`
2. GitHub Actions runs tests, builds Docker images, pushes to GHCR
3. ArgoCD Image Updater (polling every 2 minutes) detects new `:latest` tag
4. ArgoCD updates the orchestrator deployment → pods restart with new image
5. The new orchestrator uses `RUNNER_IMAGE` env var to spawn runner pods with the matching new image

### Manifest changes (this repo)

1. Push to `main` in `cassandra-k8s`
2. ArgoCD (polling every 3 minutes, or webhook for instant) detects git change
3. ArgoCD compares desired state (git) vs live state (cluster)
4. ArgoCD auto-syncs: applies additions, updates changes, prunes deletions

### Adding Obsidian vault config

```bash
kubectl -n claude-runner create secret generic obsidian-auth \
  --from-literal=OBSIDIAN_AUTH_TOKEN=<token> \
  --from-literal=OBSIDIAN_E2EE_PASSWORD=<password> \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Adding a New Service

1. Create directory: `apps/<service>/base/` with kustomize manifests
2. Create overlay: `apps/<service>/overlays/production/kustomization.yaml`
3. Create ArgoCD app: `argocd/apps/<service>.yaml` with the Application CRD
4. Push to main — ArgoCD picks it up automatically

Template for the Application CRD:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <service>
  namespace: argocd
  annotations:
    # Add image updater annotations if the service has GHCR images
    argocd-image-updater.argoproj.io/image-list: app=ghcr.io/<org>/<repo>/<image>
    argocd-image-updater.argoproj.io/app.update-strategy: latest
    argocd-image-updater.argoproj.io/write-back-method: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/DigiBugCat/cassandra-k8s.git
    targetRevision: main
    path: apps/<service>/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Troubleshooting

### ArgoCD says "OutOfSync" but won't sync

```bash
# Check sync status
kubectl -n argocd get app claude-runner -o yaml | grep -A 20 status:

# Force sync
argocd app sync claude-runner --force

# Or via kubectl
kubectl -n argocd patch application claude-runner --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD","prune":true}}}'
```

### Image Updater not detecting new images

```bash
# Check Image Updater logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-image-updater -f

# Verify GHCR credentials
kubectl -n argocd get secret ghcr-credentials

# Test registry access manually
kubectl -n argocd exec deploy/argocd-image-updater -- \
  argocd-image-updater test ghcr.io/digibugcat/claude-agent-runner/orchestrator
```

### Secrets got pruned by ArgoCD

By default, ArgoCD won't prune secrets created imperatively (outside git). If it does:

1. Add the annotation to protect the secret:
   ```bash
   kubectl -n claude-runner annotate secret claude-tokens \
     argocd.argoproj.io/sync-options=Prune=false
   ```

2. Or use SealedSecrets / External Secrets Operator for git-managed secrets
