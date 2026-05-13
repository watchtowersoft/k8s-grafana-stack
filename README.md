# k8s-grafana-stack

Cloud-agnostic Kubernetes observability stack covering all three pillars — metrics, logs, and traces — wired together in Grafana.

## Stack

| Component | Role | Image |
|---|---|---|
| **Prometheus** | Metrics scraping & storage | `prom/prometheus:v2.51.0` |
| **kube-state-metrics** | K8s object metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.12.0` |
| **node-exporter** | Host/node metrics (DaemonSet) | `prom/node-exporter:v1.8.0` |
| **Loki** | Log aggregation | `grafana/loki:2.9.6` |
| **Alloy** | Logs + metrics scraping + OTLP receiver (DaemonSet) | `grafana/alloy:v1.3.1` |
| **Tempo** | Distributed tracing | `grafana/tempo:2.4.2` |
| ~~OTel Collector~~ | Replaced by Alloy | — |
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
                             │            │         ┌───┴────────────┐
                             ▼            ▼         ▼traces  metrics │logs
                           Loki     Prometheus    Tempo     Prom     Loki
                                         ▲
                               node-exporter (DaemonSet)
                               kube-state-metrics
                               kubelet / cAdvisor
                               annotated pods
                                          │
                                     Grafana (all three datasources pre-wired)
```

## Quick Start

### Prerequisites
- `kubectl` configured against your cluster
- `kustomize` v5+ **or** `kubectl` v1.27+ (ships with kustomize built in)

### Deploy

```bash
# Full stack
kubectl apply -k .

# Or use the helper script
./scripts/deploy.sh
```

### Access Grafana locally

```bash
./scripts/port-forward.sh
# then open http://localhost:3000  (admin / admin)
```

### Tear down

```bash
./scripts/teardown.sh

# PVCs are preserved — delete manually if you want a clean slate:
kubectl delete pvc --all -n monitoring
```

## Directory Layout

```
k8s-grafana-stack/
├── kustomization.yaml          # root — apply this
├── namespaces/
│   └── monitoring.yaml
├── metrics/
│   ├── prometheus/             # RBAC, config, PVC, Deployment, Service
│   ├── kube-state-metrics/
│   └── node-exporter/         # DaemonSet
├── logging/
│   ├── loki/                  # config, PVC, Deployment, Service
│   └── alloy/                 # RBAC, config, DaemonSet, Services (cluster + OTLP)
├── tracing/
│   └── tempo/                 # config, PVC, Deployment, Service
├── grafana/
│   ├── configmap-datasources.yaml   # Prometheus + Loki + Tempo pre-wired
│   ├── configmap-dashboards.yaml    # dashboard provider config
│   ├── pvc.yaml
│   ├── deployment.yaml
│   └── service.yaml           # NodePort :3000
└── scripts/
    ├── deploy.sh
    ├── teardown.sh
    └── port-forward.sh
```

## Instrumenting Your Apps

Send telemetry from any app directly to Alloy:

```
# gRPC  (preferred)
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4317

# HTTP
OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy.monitoring.svc.cluster.local:4318
```

Alloy fans out automatically — traces → Tempo, metrics → Prometheus remote write, logs → Loki.
No separate OTel Collector needed.

For pod logs you don't need to change anything; Promtail picks them up from `/var/log/pods` on every node.

## Auto-Scrape Pods/Services

Add these annotations to any pod or service to have Prometheus scrape it:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"       # your metrics port
  prometheus.io/path: "/metrics"   # optional, defaults to /metrics
```

## Recommended Grafana Dashboards

Import these from grafana.com (Dashboards → Import → enter ID):

| ID | Name |
|---|---|
| `1860` | Node Exporter Full |
| `13770` | Kubernetes All-in-one Cluster Monitoring |
| `15141` | Kubernetes / Loki Logs |
| `16098` | Tempo / Tracing |

## Customisation Notes

### Storage class
All PVCs leave `storageClassName` commented out (uses cluster default). Uncomment and set it to target a specific storage class for your environment.

### Credentials
Grafana admin credentials are set via env vars in [grafana/deployment.yaml](grafana/deployment.yaml). Change them before exposing the service externally, or replace with a `secretKeyRef`.

### Retention
- Prometheus: 15 days (`--storage.tsdb.retention.time=15d` in [metrics/prometheus/deployment.yaml](metrics/prometheus/deployment.yaml))
- Loki: 7 days (`retention_period: 168h` in [logging/loki/configmap.yaml](logging/loki/configmap.yaml))
- Tempo: 48 hours (`block_retention: 48h` in [tracing/tempo/configmap.yaml](tracing/tempo/configmap.yaml))

### Alloy clustering
Alloy uses a hash-ring to distribute scrape targets across DaemonSet pods. Targets marked `clustering { enabled = true }` are scraped by exactly one Alloy instance — preventing duplicate time series for cluster-wide targets (kube-state-metrics, kubelet, etc.). Node-exporter is intentionally *not* clustered so each pod scrapes its own node.

### Production considerations
- Replace single-replica Deployments with StatefulSets for Prometheus/Loki/Tempo
- Add Alertmanager for alert routing
- Use object storage (S3/GCS/MinIO) for Loki and Tempo instead of local filesystem
- Add NetworkPolicies to restrict traffic between components
- Pin `nodePort` in [grafana/service.yaml](grafana/service.yaml) or add an Ingress resource
