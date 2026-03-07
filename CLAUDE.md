# CLAUDE.md — Cassandra k8s

## What This Is

k8s deployment repo for all Cassandra services. ArgoCD watches this repo and auto-applies changes. Helm charts for app workloads, kustomize for shared infra (monitoring).

**This repo contains only deployment manifests.** Application code lives in separate repos — their CI pipelines build and push images to GHCR. ArgoCD Image Updater detects new images and triggers rollouts.

## Repo Structure

```
cassandra-k8s/
├── apps/
│   └── claude-runner/              # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml             # Defaults
│       ├── values-dev.yaml         # Dev overrides (smaller resources, shorter timeouts)
│       ├── values-production.yaml  # Prod overrides (full resources, obsidian enabled)
│       └── templates/
├── monitoring/                     # Observability stack (kustomize, shared)
│   ├── base/
│   └── overlays/production/
├── argocd/
│   ├── app-of-apps.yaml            # Root Application
│   ├── image-updater.yaml          # GHCR registry config
│   └── apps/                       # Per-env ArgoCD Applications
│       ├── claude-runner-dev.yaml
│       ├── claude-runner-production.yaml
│       └── monitoring.yaml
├── scripts/
│   └── bootstrap.sh                # One-time cluster setup
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
Push code to claude-agent-runner
  → GitHub CI: test → build → push to GHCR
  → ArgoCD Image Updater: detects new tag → updates both dev + prod

Push manifest change to cassandra-k8s
  → ArgoCD: detects git change → auto-syncs both environments
```

## Secrets

Managed via **Sealed Secrets** — encrypted in git, decrypted in-cluster.

```bash
# Seal a value for production
echo -n 'sk-ant-oat-...' | kubeseal --raw --namespace claude-runner --name claude-tokens --from-file=/dev/stdin

# Seal a value for dev
echo -n 'sk-ant-oat-...' | kubeseal --raw --namespace claude-runner-dev --name claude-tokens --from-file=/dev/stdin

# Paste into values-production.yaml or values-dev.yaml:
#   sealedSecrets:
#     claudeTokens:
#       CLAUDE_CODE_OAUTH_TOKEN: "AgBy3i4OJSWK+..."
```

Sealed values are namespace-scoped — a value sealed for `claude-runner` won't work in `claude-runner-dev`.

## Commands

```bash
# Bootstrap (one-time)
./scripts/bootstrap.sh

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
