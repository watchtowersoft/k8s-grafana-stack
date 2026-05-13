#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Deploying Grafana observability stack..."
kubectl apply -k "$ROOT_DIR"

echo ""
echo "==> Waiting for deployments to become ready..."
kubectl rollout status deployment/prometheus    -n monitoring --timeout=120s
kubectl rollout status deployment/loki         -n monitoring --timeout=120s
kubectl rollout status deployment/tempo        -n monitoring --timeout=120s
kubectl rollout status deployment/otel-collector -n monitoring --timeout=120s
kubectl rollout status deployment/grafana      -n monitoring --timeout=120s

echo ""
echo "==> Stack is ready."
echo "    Run scripts/port-forward.sh to access the UIs locally."
