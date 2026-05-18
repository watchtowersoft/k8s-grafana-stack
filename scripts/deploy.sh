#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OVERLAY="${1:-overlays/production}"
TARGET="$ROOT_DIR/$OVERLAY"

if [ ! -d "$TARGET" ]; then
  echo "ERROR: Overlay not found: $OVERLAY"
  echo ""
  echo "  Create your production overlay first:"
  echo "    cp -r overlays/example overlays/production"
  echo "    \$EDITOR overlays/production/grafana-credentials.env"
  exit 1
fi

# ---------------------------------------------------------------------------
# Check for a default StorageClass
# ---------------------------------------------------------------------------
DEFAULT_SC=$(kubectl get storageclass \
  -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' \
  2>/dev/null || true)

if [ -z "$DEFAULT_SC" ]; then
  echo "WARNING: No default StorageClass found — PVCs will not bind."
  echo "         A local-path-provisioner is included in the base."
  echo "         It will be applied as part of this deployment."
  echo ""
fi

echo "==> Deploying from overlay: $OVERLAY"
kubectl apply -k "$TARGET"

echo ""
echo "==> Waiting for deployments to become ready..."
kubectl rollout status deployment/prometheus  -n monitoring --timeout=120s
kubectl rollout status deployment/loki        -n monitoring --timeout=120s
kubectl rollout status deployment/tempo       -n monitoring --timeout=120s
kubectl rollout status deployment/grafana     -n monitoring --timeout=120s
kubectl rollout status daemonset/alloy        -n monitoring --timeout=120s

echo ""
echo "==> Stack is ready."
echo "    Run scripts/port-forward.sh to access the UIs locally."
