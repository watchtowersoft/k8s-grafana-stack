#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Removing Grafana observability stack..."
kubectl delete -k "$ROOT_DIR" --ignore-not-found

echo ""
echo "    PersistentVolumeClaims are NOT deleted automatically."
echo "    To remove them run:"
echo "      kubectl delete pvc --all -n monitoring"
