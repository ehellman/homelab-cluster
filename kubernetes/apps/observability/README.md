# Observability Stack

This stack provides monitoring, metrics, and telemetry for the Kubernetes cluster.

## Architecture

```
                                    +------------------+
                                    |     Grafana      |
                                    |   (dashboards)   |
                                    +--------+---------+
                                             |
                                             | queries
                                             v
+-------------------+              +-------------------+
|  Your Apps        |   OTLP       |    Prometheus     |
|  (metrics/traces) | -----------> |  (metrics store)  |
+-------------------+              +-------------------+
                                             ^
                                             | scrapes
         +-----------------------------------+-----------------------------------+
         |                   |                   |                   |           |
+--------+--------+ +--------+--------+ +--------+--------+ +--------+--------+  |
| node-exporter   | | kube-state-     | | kubelet         | | OpenTelemetry   |  |
| (node metrics)  | | metrics (k8s)   | | (containers)    | | Collector       |--+
+-----------------+ +-----------------+ +-----------------+ +-----------------+
                                                              receives OTLP from apps
```

## Components

| Component | Purpose | Replicas | Storage |
|-----------|---------|----------|---------|
| **Prometheus** | Time-series database for metrics | 2 | 50Gi each (ceph-block) |
| **Alertmanager** | Alert routing and notifications | 2 | 1Gi each (ceph-block) |
| **Grafana** | Visualization dashboards | 1 | 10Gi (ceph-block) |
| **OpenTelemetry Collector** | Receives OTLP telemetry from apps | DaemonSet | - |
| **node-exporter** | Exposes node-level metrics | DaemonSet | - |
| **kube-state-metrics** | Exposes Kubernetes object metrics | 1 | - |

## Data Flow

1. **Metrics from infrastructure:**
   - `node-exporter` exposes CPU, memory, disk, network per node
   - `kube-state-metrics` exposes pod counts, deployment status, etc.
   - `kubelet` exposes container-level metrics
   - Prometheus scrapes all of these every 30s

2. **Metrics from applications:**
   - Apps send OTLP to OpenTelemetry Collector (port 4317/4318)
   - Collector forwards to Prometheus via remote-write
   - Or: Apps expose `/metrics` endpoint, Prometheus scrapes directly

3. **Visualization:**
   - Grafana queries Prometheus
   - Pre-configured dashboards for nodes, pods, Kubernetes, Flux, PostgreSQL

## Accessing Grafana

```bash
# Port-forward to access locally
kubectl port-forward -n observability svc/grafana 3000:80

# Open http://localhost:3000
# Login: admin / (password from 1Password "grafana" item)
```

## Sending Telemetry from Apps

Configure your app to send OTLP to the collector:

```yaml
# For apps running in the cluster
OTEL_EXPORTER_OTLP_ENDPOINT: "http://opentelemetry-collector.observability:4317"

# Or use HTTP
OTEL_EXPORTER_OTLP_ENDPOINT: "http://opentelemetry-collector.observability:4318"
```

## Key Configuration Decisions

1. **Grafana deployed separately** - Industry standard for flexibility and independent upgrades

2. **Prometheus 2 replicas** - HA setup, both scrape independently (no data loss if one dies)

3. **14-day retention, 45GB limit** - Whichever comes first triggers data deletion

4. **`*SelectorNilUsesHelmValues: false`** - Prometheus discovers ALL ServiceMonitors cluster-wide, not just ones from kube-prometheus-stack

5. **kubeProxy disabled** - We use Cilium with eBPF, no kube-proxy running

6. **OpenTelemetry DaemonSet mode** - Runs on every node for low-latency local collection

## Dashboards

Pre-configured dashboards are loaded automatically:

| Folder | Dashboards |
|--------|------------|
| General | Node Exporter Full, CloudNative-PG |
| Kubernetes | API Server, CoreDNS, Global, Namespaces, Nodes, Pods |
| Flux | Cluster, Control Plane |

Additional dashboards from kube-prometheus-stack are loaded via sidecar (ConfigMaps with `grafana_dashboard` label).

## Useful Commands

```bash
# Check all observability pods
kubectl get pods -n observability

# Check Prometheus targets (what it's scraping)
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets

# Check Alertmanager
kubectl port-forward -n observability svc/kube-prometheus-stack-alertmanager 9093:9093

# View OpenTelemetry Collector logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector -f

# Check ServiceMonitors (what Prometheus should scrape)
kubectl get servicemonitors -A
```

## Future Additions

| Component | Purpose |
|-----------|---------|
| **Loki** | Log aggregation (OpenTelemetry would export logs here) |
| **Tempo** | Distributed tracing (OpenTelemetry would export traces here) |
| **Alertmanager config** | Slack/Discord/PagerDuty notifications |
