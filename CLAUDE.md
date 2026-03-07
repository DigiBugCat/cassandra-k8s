# CLAUDE.md — Cassandra GitOps

## What This Is

GitOps repo for all Cassandra infrastructure deployed to k8s/k3d. ArgoCD watches this repo and auto-applies changes.

**This repo contains only deployment manifests.** Application code lives in separate repos — their CI pipelines build and push images to GHCR. ArgoCD Image Updater detects new images and triggers rollouts.

## Repo Structure

```
cassandra-gitops/
├── apps/
│   └── claude-runner/           # Claude Agent Runner (orchestrator + runner pods)
│       ├── base/                # Base kustomize manifests
│       └── overlays/
│           └── production/      # Production overrides (image tags, env)
├── monitoring/                  # Observability stack (shared across all apps)
│   ├── base/                    # VictoriaMetrics, VictoriaLogs, Vector, Grafana
│   └── overlays/
│       └── production/
├── argocd/
│   ├── namespace.yaml           # ArgoCD namespace
│   ├── image-updater.yaml       # GHCR registry config for Image Updater
│   ├── app-of-apps.yaml         # Root Application (manages all others)
│   └── apps/                    # Individual ArgoCD Application CRDs
│       ├── claude-runner.yaml
│       └── monitoring.yaml
├── scripts/
│   └── bootstrap.sh             # One-time cluster setup
└── docs/
    └── setup.md                 # Full setup guide
```

## How It Works

```
Developer pushes code to claude-agent-runner
  → GitHub CI: test → build → push images to GHCR
  → ArgoCD Image Updater (in cluster): detects new image tag
  → ArgoCD: updates deployment → pods roll out with new image

Developer pushes manifest change to cassandra-gitops
  → ArgoCD: detects git change → auto-syncs → applies to cluster
```

## Adding a New Service

1. Create `apps/<service-name>/base/` with kustomize manifests
2. Create `apps/<service-name>/overlays/production/kustomization.yaml`
3. Create `argocd/apps/<service-name>.yaml` (ArgoCD Application CRD)
4. Push — ArgoCD picks it up automatically via the app-of-apps pattern

## Commands

```bash
# Bootstrap (one-time)
./scripts/bootstrap.sh

# Check ArgoCD sync status
kubectl -n argocd get applications

# Force sync
kubectl -n argocd patch application claude-runner --type merge -p '{"operation":{"sync":{}}}'

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8443:443
# https://localhost:8443 — admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# Validate kustomize
kubectl kustomize apps/claude-runner/overlays/production
kubectl kustomize monitoring/overlays/production
```

## Secrets

Secrets are in the base manifests with `REPLACE_ME` placeholders. On first deploy, update them imperatively:

```bash
kubectl -n claude-runner create secret generic claude-tokens \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat-... \
  --dry-run=client -o yaml | kubectl apply -f -
```

ArgoCD won't overwrite secrets that already exist (they're excluded from prune by default for Opaque secrets).

## Image Update Flow

ArgoCD Image Updater watches GHCR for:
- `ghcr.io/digibugcat/claude-agent-runner/orchestrator`
- `ghcr.io/digibugcat/claude-agent-runner/runner`

When a new `:latest` tag is pushed, Image Updater tells ArgoCD to update the deployment. The write-back method is `argocd` (parameter override), not git-commit — so no commits are pushed back to this repo.

The runner image is special: the orchestrator spawns runner pods programmatically via the k8s API. The `RUNNER_IMAGE` env var in the deployment tells the orchestrator which image to use. When Image Updater bumps the orchestrator, the new orchestrator picks up the latest runner image tag from its env.
