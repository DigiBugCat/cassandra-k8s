# CLAUDE.md — Cassandra k8s

## What This Is

k8s deployment repo for all Cassandra services. ArgoCD watches this repo and auto-applies changes. Helm charts for app workloads.

**This repo contains only deployment manifests.** Application code lives in separate repos — their CI pipelines build and push `latest` images to the local registry (`172.20.0.161:30500`). ArgoCD syncs Helm charts that use `latest` with `pullPolicy: Always`.

## Repo Structure

```
cassandra-k8s/
├── apps/
│   ├── claude-runner/              # Helm chart — orchestrator + runner
│   │   ├── Chart.yaml
│   │   ├── values.yaml             # Defaults
│   │   ├── values-dev.yaml         # Dev overrides (smaller resources, shorter timeouts)
│   │   ├── values-production.yaml  # Prod overrides (full resources, obsidian enabled)
│   │   └── templates/
│   ├── cassandra-yt-mcp/           # Helm chart — GPU transcription backend
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│   ├── registry/                   # Helm chart — local Docker registry
│   └── arc-runners/                # Helm wrapper for ARC runner secrets
├── argocd/
│   ├── app-of-apps.yaml            # Root Application
│   └── apps/                       # Per-env ArgoCD Applications
│       ├── claude-runner-dev.yaml
│       ├── claude-runner-production.yaml
│       ├── cassandra-yt-mcp.yaml
│       ├── registry.yaml
│       ├── arc-controller.yaml
│       ├── arc-runner-scale-set-*.yaml
│       ├── arc-runner-secrets.yaml
│       ├── vm-k8s-stack.yaml
│       └── observability-dashboards.yaml
├── scripts/
│   ├── bootstrap.sh                # One-time cluster setup
│   └── test-integration.sh         # Local chart + Argo smoke validation
└── docs/
    └── setup.md
```

## Environments

| Environment | Namespace | Values | Notes |
|-------------|-----------|--------|-------|
| Dev | `claude-runner-dev` | `values.yaml` + `values-dev.yaml` | Smaller resources, 1 warm pod, 30min timeout |
| Production | `claude-runner` | `values.yaml` + `values-production.yaml` | Full resources, 2 warm pods, 4hr timeout, Obsidian enabled |

Same Helm chart, different value files, different namespaces. Both deployed to the same cluster.

## How It Works

```
Push code to claude-agent-runner / cassandra-yt-mcp
  → GitHub CI: test → build → push :latest to local registry (172.20.0.161:30500)
  → Restart orchestrator or wait for next pod creation to pick up new image

Push manifest change to cassandra-k8s
  → ArgoCD: detects git change → auto-syncs both environments
```

## Secrets

Managed manually via `kubectl create secret` — **nothing in git**. Raw values stored in `cassandra-stack/env/` (private repo).

### claude-runner (namespace: `claude-runner`)

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

### claude-runner-dev (namespace: `claude-runner-dev`)

```bash
kubectl create secret generic claude-tokens --namespace claude-runner-dev \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN=<token>

kubectl create secret generic git-tokens --namespace claude-runner-dev \
  --from-literal=GITHUB_TOKEN=<token>
```

### cassandra-yt-mcp (namespace: `cassandra-yt-mcp`)

```bash
kubectl create secret generic cassandra-yt-mcp-backend --namespace cassandra-yt-mcp \
  --from-literal=BACKEND_API_TOKEN=<token>

kubectl create secret generic cloudflare-tunnel --namespace cassandra-yt-mcp \
  --from-literal=token=<tunnel-token>
```

## Commands

```bash
# Bootstrap (one-time)
./scripts/bootstrap.sh

# Repo-local integration validation
./scripts/test-integration.sh

# Check sync status
kubectl -n argocd get applications

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8443:443

# Force sync an app
kubectl -n argocd patch application claude-runner-production --type merge -p '{"operation":{"sync":{}}}'

# Validate Helm chart locally
helm template claude-runner apps/claude-runner -f apps/claude-runner/values.yaml -f apps/claude-runner/values-dev.yaml --namespace claude-runner-dev
```

## Adding a New Service

1. Create `apps/<service>/` as a Helm chart (Chart.yaml, values.yaml, templates/)
2. Add `values-dev.yaml` and `values-production.yaml`
3. Create ArgoCD Applications in `argocd/apps/` (one per environment)
4. Push — app-of-apps picks it up automatically
