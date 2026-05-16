#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Check for a default StorageClass — required for PVCs to bind
# ---------------------------------------------------------------------------
DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)

if [ -z "$DEFAULT_SC" ]; then
  echo "WARNING: No default StorageClass found."
  echo "         PVCs will remain unbound and pods will fail to schedule."
  echo ""
  echo "         To install local-path-provisioner (works on bare-metal/Vagrant):"
  echo "           kubectl apply -f storage/local-path-provisioner.yaml"
  echo ""
  read -r -p "Continue anyway? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
else
  echo "==> Default StorageClass: $DEFAULT_SC"
fi

echo ""
echo "==> Deploying Grafana observability stack..."
kubectl apply -k "$ROOT_DIR"

echo ""
echo "==> Waiting for deployments to become ready..."
kubectl rollout status deployment/prometheus     -n monitoring --timeout=120s
kubectl rollout status deployment/loki          -n monitoring --timeout=120s
kubectl rollout status deployment/tempo         -n monitoring --timeout=120s
kubectl rollout status deployment/grafana       -n monitoring --timeout=120s
kubectl rollout status daemonset/alloy          -n monitoring --timeout=120s

echo ""
echo "==> Stack is ready."
echo "    Run scripts/port-forward.sh to access the UIs locally."
