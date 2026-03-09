#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORK_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK_DIR"
}

trap cleanup EXIT

log() {
  printf '==> %s\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -Fq -- "$needle" "$file"; then
    fail "Expected '$needle' in $file"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$file"; then
    fail "Did not expect '$needle' in $file"
  fi
}

render_chart() {
  local output_file="$1"
  shift

  helm template "$@" > "$output_file"
}

dry_run_apply() {
  local file="$1"
  kubectl apply --dry-run=client --validate=false -f "$file" >/dev/null
}

assert_argo_source_contracts() {
  local dev_app="$REPO_DIR/argocd/apps/claude-runner-dev.yaml"
  local prod_app="$REPO_DIR/argocd/apps/claude-runner-production.yaml"
  local app_of_apps="$REPO_DIR/argocd/app-of-apps.yaml"

  log "Checking Argo source contracts"
  assert_contains "$dev_app" "path: apps/claude-runner"
  assert_contains "$dev_app" "- values.yaml"
  assert_contains "$dev_app" "- values-dev.yaml"

  assert_contains "$prod_app" "path: apps/claude-runner"
  assert_contains "$prod_app" "- values.yaml"
  assert_contains "$prod_app" "- values-production.yaml"

  assert_contains "$app_of_apps" "path: argocd/apps"
}

main() {
  local claude_dev="$WORK_DIR/claude-runner-dev.yaml"
  local claude_prod="$WORK_DIR/claude-runner-production.yaml"
  local yt_mcp="$WORK_DIR/cassandra-yt-mcp.yaml"
  local registry="$WORK_DIR/registry.yaml"

  cd "$REPO_DIR"

  log "Rendering claude-runner dev manifests"
  render_chart \
    "$claude_dev" \
    claude-runner-dev \
    apps/claude-runner \
    --namespace claude-runner-dev \
    -f apps/claude-runner/values.yaml \
    -f apps/claude-runner/values-dev.yaml
  dry_run_apply "$claude_dev"

  log "Checking claude-runner dev contracts"
  assert_contains "$claude_dev" "name: claude-orchestrator-claude-runner-dev"
  assert_contains "$claude_dev" "nodePort: 30180"
  assert_contains "$claude_dev" "nodePort: 30181"
  assert_not_contains "$claude_dev" "name: ENABLE_TENANTS"
  assert_not_contains "$claude_dev" "key: ADMIN_API_KEY"
  assert_not_contains "$claude_dev" "name: OBSIDIAN_AUTH_TOKEN"
  assert_not_contains "$claude_dev" "name: OBSIDIAN_E2EE_PASSWORD"
  assert_not_contains "$claude_dev" "name: cloudflared"

  log "Rendering claude-runner production manifests"
  render_chart \
    "$claude_prod" \
    claude-runner-production \
    apps/claude-runner \
    --namespace claude-runner \
    -f apps/claude-runner/values.yaml \
    -f apps/claude-runner/values-production.yaml
  dry_run_apply "$claude_prod"

  log "Checking claude-runner production contracts"
  assert_contains "$claude_prod" "name: claude-orchestrator-claude-runner"
  assert_contains "$claude_prod" "nodePort: 30080"
  assert_contains "$claude_prod" "nodePort: 30081"
  assert_contains "$claude_prod" "name: ENABLE_TENANTS"
  assert_contains "$claude_prod" "key: ADMIN_API_KEY"
  assert_contains "$claude_prod" "name: OBSIDIAN_AUTH_TOKEN"
  assert_contains "$claude_prod" "name: OBSIDIAN_E2EE_PASSWORD"
  assert_contains "$claude_prod" "name: cloudflared"

  log "Rendering cassandra-yt-mcp manifests"
  render_chart \
    "$yt_mcp" \
    cassandra-yt-mcp \
    apps/cassandra-yt-mcp \
    --namespace cassandra-yt-mcp \
    -f apps/cassandra-yt-mcp/values.yaml
  dry_run_apply "$yt_mcp"

  log "Checking cassandra-yt-mcp contracts"
  assert_contains "$yt_mcp" "name: cassandra-yt-mcp"
  assert_contains "$yt_mcp" "name: cassandra-yt-mcp-worker"
  assert_contains "$yt_mcp" "path: /worker/healthz"
  assert_contains "$yt_mcp" "nvidia.com/gpu: 1"
  assert_contains "$yt_mcp" "name: cloudflared"

  log "Rendering registry manifests"
  render_chart \
    "$registry" \
    registry \
    apps/registry \
    --namespace registry \
    -f apps/registry/values.yaml
  dry_run_apply "$registry"

  log "Checking registry contracts"
  assert_contains "$registry" "nodePort: 30500"
  assert_contains "$registry" "path: /mnt/raid1/registry"

  log "Validating Argo manifests"
  kubectl apply --dry-run=client --validate=false \
    -f "$REPO_DIR/argocd/app-of-apps.yaml" \
    -f "$REPO_DIR/argocd/apps" >/dev/null
  assert_argo_source_contracts

  log "Integration validation passed"
}

main "$@"
