# Cassandra k8s

> **Disclaimer:** This repo is a personal deployment configuration. It's public for reference — you'll need to adapt secrets, namespaces, and domain names for your own setup.

Kubernetes deployment manifests for the [Cassandra](https://github.com/DigiBugCat) platform. ArgoCD watches this repo and auto-applies changes.

## What's Here

- **`apps/claude-runner/`** — Helm chart for the [Claude Agent Runner](https://github.com/DigiBugCat/claude-agent-runner) orchestrator + runner pods
- **`apps/arc-runners/`** — Self-hosted GitHub Actions runners via [ARC](https://github.com/actions/actions-runner-controller)
- **`argocd/`** — ArgoCD Applications (app-of-apps pattern) + Image Updater config
- **`monitoring/`** — VictoriaMetrics + VictoriaLogs + Vector + Grafana (kustomize)
- **`scripts/bootstrap.sh`** — One-time cluster setup (ArgoCD, Sealed Secrets, Image Updater)

## How It Works

```
Push code to claude-agent-runner
  → GitHub CI: test → build → push to GHCR
  → ArgoCD Image Updater: detects new tag → updates deployments

Push manifest change to this repo
  → ArgoCD: detects git change → auto-syncs
```

## Environments

| Environment | Namespace | Values |
|-------------|-----------|--------|
| Dev | `claude-runner-dev` | `values.yaml` + `values-dev.yaml` |
| Production | `claude-runner` | `values.yaml` + `values-production.yaml` |

Same Helm chart, different value files, different namespaces.

## Setup

```bash
# Prerequisites: kubectl pointed at your cluster, kubeseal installed
./scripts/bootstrap.sh
```

See [`docs/setup.md`](docs/setup.md) for the full guide.

## License

[MIT](LICENSE)
