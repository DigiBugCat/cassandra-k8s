# Cassandra k8s

> **Disclaimer:** This repo is a personal deployment configuration. It's public for reference — you'll need to adapt secrets, namespaces, and domain names for your own setup.

Kubernetes deployment manifests for the [Cassandra](https://github.com/DigiBugCat) platform. ArgoCD watches this repo and auto-applies changes.

## What's Here

- **`apps/claude-runner/`** — Helm chart for the [Claude Agent Runner](https://github.com/DigiBugCat/claude-agent-runner) orchestrator + runner pods
- **`apps/cassandra-yt-mcp/`** — Helm chart for the GPU transcription backend
- **`apps/registry/`** — Helm chart for the in-cluster local Docker registry
- **`apps/arc-runners/`** — Helm wrapper for manually managed ARC runner secrets
- **`argocd/`** — app-of-apps root, per-app Argo Applications, ARC and observability app definitions
- **`scripts/bootstrap.sh`** — One-time cluster setup (ArgoCD)
- **`scripts/test-integration.sh`** — local render/apply smoke validation for charts and Argo manifests

## How It Works

```
Push code to claude-agent-runner / cassandra-yt-mcp
  → ARC runners: test → build → push :latest to local registry
  → Pods pick up new image on next creation (pullPolicy: Always)

Push manifest change to this repo
  → ArgoCD: detects git change → auto-syncs
```

## Environments

| Environment | Namespace | Values |
|-------------|-----------|--------|
| Dev | `claude-runner-dev` | `values.yaml` + `values-dev.yaml` |
| Production | `claude-runner` | `values.yaml` + `values-production.yaml` |

Same Helm chart, different value files, different namespaces. Both deploy to the same cluster — ArgoCD manages them as separate Applications.

## Deploying

Everything is GitOps — push to `main` and ArgoCD handles the rest.

### Code changes (app updates)

Push to `main` in [claude-agent-runner](https://github.com/DigiBugCat/claude-agent-runner) or [cassandra-yt-mcp](https://github.com/DigiBugCat/cassandra-yt-mcp). ARC runners build Docker images → push `:latest` to local registry (`172.20.0.161:30500`). Pods pick up the new image on next creation (`pullPolicy: Always`). To force a rollout, restart the orchestrator deployment.

### Config changes (k8s manifests)

Edit the Helm values or templates in this repo and push to `main`. ArgoCD auto-syncs within 30 seconds.

- **Dev only**: edit `apps/claude-runner/values-dev.yaml`
- **Prod only**: edit `apps/claude-runner/values-production.yaml`
- **Both**: edit `apps/claude-runner/values.yaml` or templates

### Secrets

Secrets are created manually on the cluster (not in git):

```bash
# Production
kubectl create secret generic claude-tokens --namespace claude-runner \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN='sk-ant-...'

# Dev
kubectl create secret generic claude-tokens --namespace claude-runner-dev \
  --from-literal=CLAUDE_CODE_OAUTH_TOKEN='sk-ant-...'
```

See [`docs/setup.md`](docs/setup.md) for the full list of secrets per namespace.

### Useful commands

```bash
# Validate Helm + Argo manifests locally
./scripts/test-integration.sh

# Check what's deployed
kubectl -n argocd get applications

# Force sync a specific app
kubectl -n argocd patch application claude-runner-production \
  --type merge -p '{"operation":{"sync":{}}}'

# ArgoCD UI
kubectl -n argocd port-forward svc/argocd-server 8443:443

# Grafana
kubectl -n monitoring port-forward svc/grafana 3000:3000
```

## Setup

```bash
# Prerequisites: kubectl pointed at your cluster
./scripts/bootstrap.sh

# Local validation
./scripts/test-integration.sh
```

See [`docs/setup.md`](docs/setup.md) for the full guide.

## License

[MIT](LICENSE)
