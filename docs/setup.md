# Cassandra GitOps — Setup Guide

## Prerequisites

- **k3s** cluster running on pantainos (production)
- **kubectl** configured to talk to the remote cluster
- **ArgoCD** installed in-cluster (watches this repo)

## Architecture

```
Local machine (kubectl) → pantainos k3s cluster
                          ├── claude-runner namespace (production)
                          ├── claude-runner-dev namespace (dev)
                          ├── cassandra-yt-mcp namespace (GPU transcription)
                          └── argocd namespace
```

- **Images**: Built by ARC runners, pushed to local registry (`172.20.0.161:30500`)
- **Deploys**: ArgoCD Image Updater detects new tags → auto-syncs deployments
- **GPU nodes**: callsonballz (172.20.2.32) and will (172.20.2.33) — both WSL2 bridged networking, RTX 5080. Label `role=gpu-node`, taint `dedicated=gpu-node:NoSchedule`

## Secrets

All secrets are managed manually via `kubectl create secret` — nothing in git. Raw values stored in `cassandra-stack/env/` (private repo).

### claude-runner (production)

```bash
kubectl create secret generic admin-key --namespace claude-runner \
  --from-literal=ADMIN_API_KEY=<key>

kubectl create secret generic claude-tokens --namespace claude-runner \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN=<token>

kubectl create secret generic git-tokens --namespace claude-runner \
  --from-literal=GITHUB_TOKEN=<token>

kubectl create secret generic obsidian-auth --namespace claude-runner \
  --from-literal=OBSIDIAN_AUTH_TOKEN=<token> \
  --from-literal=OBSIDIAN_E2EE_PASSWORD=<password>

kubectl create secret generic cloudflare-tunnel --namespace claude-runner \
  --from-literal=token=<tunnel-token>
```

### claude-runner-dev

```bash
kubectl create secret generic claude-tokens --namespace claude-runner-dev \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN=<token>

kubectl create secret generic git-tokens --namespace claude-runner-dev \
  --from-literal=GITHUB_TOKEN=<token>
```

### cassandra-yt-mcp

```bash
kubectl create secret generic cassandra-yt-mcp-backend --namespace cassandra-yt-mcp \
  --from-literal=BACKEND_API_TOKEN=<token>

kubectl create secret generic cloudflare-tunnel --namespace cassandra-yt-mcp \
  --from-literal=token=<tunnel-token>
```

### Protecting secrets from ArgoCD pruning

Secrets created via kubectl (outside git) are safe from ArgoCD pruning by default. If needed:

```bash
kubectl -n <namespace> annotate secret <name> \
  argocd.argoproj.io/sync-options=Prune=false
```

## How Deployments Work

### Code changes (application repos)

1. Push to `main` in `claude-agent-runner` or `cassandra-yt-mcp`
2. ARC runners build images, push to local registry (`172.20.0.161:30500`)
3. ArgoCD Image Updater detects new tag → auto-syncs
4. Pods restart with new image

### Manifest changes (this repo)

1. Push to `main` in `cassandra-k8s`
2. ArgoCD detects git change → auto-syncs

## Commands

```bash
# Check sync status
kubectl -n argocd get applications

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8443:443

# Force sync an app
kubectl -n argocd patch application claude-runner-production --type merge \
  -p '{"operation":{"sync":{}}}'

# Validate Helm chart locally
helm template claude-runner apps/claude-runner \
  -f apps/claude-runner/values.yaml \
  -f apps/claude-runner/values-dev.yaml \
  --namespace claude-runner-dev
```

## Adding a New Service

1. Create `apps/<service>/` as a Helm chart (Chart.yaml, values.yaml, templates/)
2. Create ArgoCD Application in `argocd/apps/`
3. Create secrets manually via `kubectl create secret`
4. Push — app-of-apps picks it up automatically

## Troubleshooting

### ArgoCD says "OutOfSync" but won't sync

```bash
# Check sync status
kubectl -n argocd get app <app-name> -o yaml | grep -A 20 status:

# Force sync
kubectl -n argocd patch application <app-name> --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD","prune":true}}}'
```

### Image Updater not detecting new images

```bash
# Check Image Updater logs
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-image-updater -f
```
