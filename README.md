# k8s-grafana-stack

Cloud-agnostic Kubernetes observability stack covering all three pillars — metrics, logs, and traces — wired together in Grafana.

## Stack

| Component | Role | Image |
|---|---|---|
| **Prometheus** | Metrics storage + query backend (TSDB) | `prom/prometheus:v2.51.0` |
| **kube-state-metrics** | K8s object metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.12.0` |
| **node-exporter** | Host/node metrics (DaemonSet) | `prom/node-exporter:v1.8.0` |
| **Loki** | Log aggregation | `grafana/loki:2.9.6` |
| **Alloy** | Logs + metrics scraping + OTLP receiver (DaemonSet) | `grafana/alloy:v1.3.1` |
| **Tempo** | Distributed tracing | `grafana/tempo:2.4.2` |
| **Grafana** | Unified dashboards | `grafana/grafana:10.4.2` |

All resources deploy into the `monitoring` namespace.

## Data Flow

```
                        ┌─────────────────────────────────────┐
                        │           your applications          │
                        └────────────────┬────────────────────┘
                                         │ OTLP (gRPC :4317 / HTTP :4318)
                                         ▼
                     ┌───────────────────────────────────────────┐
                     │         Grafana Alloy  (DaemonSet)        │
                     │                                           │
                     │  ┌─────────┐  ┌──────────┐  ┌────────┐  │
                     │  │  logs   │  │ metrics  │  │  OTLP  │  │
                     │  │ (file)  │  │ (scrape) │  │  recv  │  │
                     │  └────┬────┘  └────┬─────┘  └───┬────┘  │
                     └───────┼────────────┼─────────────┼───────┘
                             │            │         ┌───┴──────────────┐
                             ▼            ▼     traces  metrics    logs │
                           Loki     Prometheus   Tempo   Prom      Loki
                                         ▲
                               node-exporter (DaemonSet)
                               kube-state-metrics
                               kubelet / cAdvisor
                               annotated pods
                                          │
                                     Grafana (all three datasources pre-wired)
```

Prometheus operates as a pure TSDB — Alloy handles all scraping and remote-writes metrics in.

## Quick Start

### Prerequisites
- `kubectl` configured against your cluster
- `kustomize` v5+ **or** `kubectl` v1.27+ (ships with kustomize built in)

### 1 — Create your production overlay

`overlays/production/` is **gitignored and never committed**. It must be created manually on every machine you deploy from:

```bash
cp -r overlays/example overlays/production
$EDITOR overlays/production/grafana-credentials.env
```

Set real credentials in `grafana-credentials.env`:
```
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=your-secure-password
```

> There is no root `kustomization.yaml`. Always target an overlay:
> `kubectl apply -k overlays/production` — **not** `kubectl apply -k .`

### 2 — Deploy

```bash
./scripts/deploy.sh
# or directly:
kubectl apply -k overlays/production
```

The base includes `local-path-provisioner` which creates a default StorageClass backed by hostPath volumes. If your cluster already has a default StorageClass (kind, minikube, GKE, EKS, AKS), it will just be an extra no-op resource — safe to leave in.

### 3 — Access Grafana

```bash
./scripts/port-forward.sh
# Grafana  → http://localhost:3000
# Prometheus → http://localhost:9090
# Alloy UI   → http://localhost:12345
```

### Tear down

```bash
./scripts/teardown.sh

# PVCs are preserved — delete manually for a clean slate:
kubectl delete pvc --all -n monitoring
```

### Validate before applying

```bash
./scripts/validate.sh          # uses overlays/example by default
./scripts/validate.sh overlays/production
```

Runs kustomize build, kubeconform schema validation, and Alloy config syntax check.

## Directory Layout

```
k8s-grafana-stack/
├── base/                              # generic, cluster-agnostic manifests (committed)
│   ├── kustomization.yaml
│   ├── storage/                       # local-path-provisioner for bare-metal clusters
│   ├── namespaces/
│   ├── metrics/
│   │   ├── prometheus/                # TSDB backend only — Alloy handles scraping
│   │   ├── kube-state-metrics/
│   │   └── node-exporter/
│   ├── logging/
│   │   ├── loki/
│   │   └── alloy/                     # unified agent: logs + metrics + OTLP
│   ├── tracing/
│   │   └── tempo/
│   └── grafana/
├── overlays/
│   ├── example/                       # committed — safe placeholder values
│   │   ├── kustomization.yaml         # patch examples for storage class, resources, etc.
│   │   └── grafana-credentials.env
│   └── production/                    # gitignored — never committed, create manually
│       ├── kustomization.yaml
│       └── grafana-credentials.env
└── scripts/
    ├── deploy.sh                      # ./deploy.sh [overlay path]
    ├── validate.sh                    # ./validate.sh [overlay path]
    ├── teardown.sh
    └── port-forward.sh
```

## Instrumenting Your Apps

Send telemetry from any app directly to Alloy:

```bash
# gRPC (preferred)
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4317

# HTTP
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4318
```

Alloy fans out automatically — traces → Tempo, metrics → Prometheus, logs → Loki. No separate collector needed.

Pod logs require no instrumentation — Alloy tails `/var/log/pods` on every node automatically.

## Auto-Scrape Pods

Add these annotations to any pod in any namespace to have Alloy scrape it:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"   # optional, defaults to /metrics
```

## Customising via Overlays

Cluster-specific changes belong in `overlays/production/kustomization.yaml`, not in `base/`. See `overlays/example/kustomization.yaml` for commented examples including:

- Pinning a specific StorageClass across all PVCs
- Increasing storage sizes for larger clusters
- Adding node affinity to schedule the stack on dedicated nodes

### Retention

| Component | Default | Config location |
|---|---|---|
| Prometheus | 15 days | `--storage.tsdb.retention.time` in [base/metrics/prometheus/deployment.yaml](base/metrics/prometheus/deployment.yaml) |
| Loki | 7 days | `retention_period` in [base/logging/loki/configmap.yaml](base/logging/loki/configmap.yaml) |
| Tempo | 48 hours | `block_retention` in [base/tracing/tempo/configmap.yaml](base/tracing/tempo/configmap.yaml) |

### Alloy clustering

Alloy uses a hash-ring to distribute scrape targets across DaemonSet pods. Targets marked `clustering { enabled = true }` are scraped by exactly one Alloy instance — preventing duplicate time series for cluster-wide targets (kube-state-metrics, kubelet, cAdvisor). Node-exporter is intentionally not clustered so each pod scrapes its own node.

## Recommended Grafana Dashboards

Import from grafana.com (Dashboards → Import → enter ID):

| ID | Name |
|---|---|
| `1860` | Node Exporter Full |
| `13770` | Kubernetes All-in-one Cluster Monitoring |
| `15141` | Kubernetes / Loki Logs |
| `16098` | Tempo / Tracing |

## Production Considerations

- Replace single-replica Deployments with StatefulSets for Prometheus/Loki/Tempo
- Add Alertmanager for alert routing
- Use object storage (S3/GCS/MinIO) for Loki and Tempo instead of local filesystem
- Add NetworkPolicies to restrict traffic between components
- Add an Ingress resource for Grafana instead of relying on NodePort/port-forward
