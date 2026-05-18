#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OVERLAY="${1:-overlays/example}"
TARGET="$ROOT_DIR/$OVERLAY"
MANIFESTS=/tmp/k8s-grafana-stack-manifests.yaml
ALLOY_CFG=/tmp/k8s-grafana-stack-alloy.alloy

cd "$ROOT_DIR"

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  [PASS] $1"; ((PASS++)) || true; }
fail() { echo "  [FAIL] $1"; ((FAIL++)) || true; }
skip() { echo "  [SKIP] $1 — $2"; ((SKIP++)) || true; }

# ---------------------------------------------------------------------------
# 1. Kustomize build — catches missing resources, bad references, YAML errors
# ---------------------------------------------------------------------------
echo ""
echo "==> 1/3  kustomize build ($OVERLAY)"
if kustomize build "$TARGET" > "$MANIFESTS" 2>&1; then
  ok "kustomize build"
else
  cat "$MANIFESTS"
  fail "kustomize build"
fi

# ---------------------------------------------------------------------------
# 2. kubeconform — validates every resource against K8s OpenAPI schemas
# ---------------------------------------------------------------------------
echo ""
echo "==> 2/3  kubeconform schema validation"
if command -v kubeconform &>/dev/null; then
  if kubeconform -strict -ignore-missing-schemas -output pretty "$MANIFESTS"; then
    ok "kubeconform"
  else
    fail "kubeconform"
  fi
else
  skip "kubeconform" "not installed — brew install kubeconform"
fi

# ---------------------------------------------------------------------------
# 3. Alloy config — extract from ConfigMap and validate with alloy fmt
# ---------------------------------------------------------------------------
echo ""
echo "==> 3/3  Alloy config syntax (alloy fmt)"

python3 - <<'EOF' > "$ALLOY_CFG"
import yaml, sys
with open("base/logging/alloy/configmap.yaml") as f:
    cm = yaml.safe_load(f)
config = cm.get("data", {}).get("config.alloy")
if not config:
    sys.exit("config.alloy key not found in ConfigMap")
print(config)
EOF

if command -v alloy &>/dev/null; then
  if alloy fmt "$ALLOY_CFG" > /dev/null; then
    ok "alloy fmt (local binary)"
  else
    fail "alloy fmt"
  fi
elif command -v docker &>/dev/null; then
  if docker run --rm \
       -v "${ALLOY_CFG}:/etc/alloy/config.alloy:ro" \
       grafana/alloy:v1.3.1 \
       fmt /etc/alloy/config.alloy > /dev/null; then
    ok "alloy fmt (docker)"
  else
    fail "alloy fmt (docker)"
  fi
else
  skip "alloy fmt" "neither alloy binary nor docker found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "  Passed: $PASS  Failed: $FAIL  Skipped: $SKIP"
echo ""

[ "$FAIL" -eq 0 ]
