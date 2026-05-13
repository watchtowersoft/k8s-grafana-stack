#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  echo ""
  echo "==> Stopping port-forwards..."
  kill 0
}
trap cleanup EXIT INT TERM

echo "==> Starting port-forwards (Ctrl-C to stop all)"
echo ""
echo "    Grafana     → http://localhost:3000  (admin / admin)"
echo "    Prometheus  → http://localhost:9090"
echo "    Loki        → http://localhost:3100"
echo "    Tempo       → http://localhost:3200"
echo "    Alloy UI    → http://localhost:12345"
echo "    OTLP gRPC   → localhost:4317  (send via alloy service)"
echo "    OTLP HTTP   → localhost:4318  (send via alloy service)"
echo ""

kubectl port-forward -n monitoring svc/grafana    3000:3000  &
kubectl port-forward -n monitoring svc/prometheus 9090:9090  &
kubectl port-forward -n monitoring svc/loki       3100:3100  &
kubectl port-forward -n monitoring svc/tempo      3200:3200  &
kubectl port-forward -n monitoring svc/alloy      12345:12345 4317:4317 4318:4318 &

wait
