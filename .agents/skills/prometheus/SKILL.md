---
name: prometheus
description: |
  Query Prometheus for cluster metrics, alerts, and health via PromQL. Port-forward to the
  in-cluster Prometheus and run instant/range queries, list firing alerts, and inspect scrape targets.

  Use when: (1) Investigating cluster health, CPU/memory pressure, or resource utilization,
  (2) Checking which alerts are firing, (3) Diagnosing pod restarts or crash loops via metrics,
  (4) Verifying scrape targets are up, (5) Running ad-hoc PromQL against the homelab.

  Triggers: "what's the CPU usage", "show firing alerts", "check memory pressure", "query prometheus",
  "promql", "are targets up", "pod restarts", "node load", "scrape targets", "alertmanager".
user-invocable: false
---

# Prometheus Querying

In-cluster metrics live in the `observability` namespace, served by the `kube-prometheus-stack`
HelmRelease (chart v86.2.0). This skill is for **querying metrics** over HTTP. It is unrelated to
the read-only flux-operator-mcp, which is for Flux/GitOps state — use this for metrics, not Flux.

## Endpoints

| Component | In-cluster DNS |
|-|-|
| Prometheus | `kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090` |
| Alertmanager | `kube-prometheus-stack-alertmanager.observability:9093` |

## Setup: port-forward

The API is plain HTTP inside the cluster. Forward a local port, then curl `localhost:9090`:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
# Alertmanager (optional)
kubectl -n observability port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 &
```

Stop forwards with `kill %1` (or `pkill -f port-forward`) when done.

## Quick queries via promql.sh

The bundled `scripts/promql.sh` wraps `/api/v1/*` and defaults to `PROMETHEUS_URL=http://localhost:9090`.
Start the port-forward above first.

```bash
S=.agents/skills/prometheus/scripts/promql.sh

$S query 'up'                                   # instant query
$S range 'rate(node_cpu_seconds_total[5m])' --start 1h --step 1m   # range query
$S alerts --firing                              # active alerts only
$S rules                                         # alerting + recording rules
$S series '{job="node-exporter"}'               # series matching a selector
$S labels job                                    # values for a label
$S health                                         # ready/healthy + build info
```

## Running queries with curl directly

If you prefer no script, hit the API directly. URL-encode the PromQL.

```bash
# Instant query
curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=up' | jq '.data.result'

# Range query (Unix start/end + step)
curl -sG http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=rate(node_cpu_seconds_total[5m])' \
  --data "start=$(date -d '1 hour ago' +%s)" --data "end=$(date +%s)" --data 'step=60' | jq '.data.result'

# Firing alerts
curl -s http://localhost:9090/api/v1/alerts \
  | jq -r '.data.alerts[] | select(.state=="firing") | "\(.labels.alertname) [\(.labels.severity)]"'
```

The `ALERTS` metric also exposes alert state as a time series:

```bash
curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=ALERTS{alertstate="firing"}' | jq '.data.result'
```

## Common investigation queries

```promql
# Node CPU usage %
avg(1 - rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100

# Node memory usage %
(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100

# Pods not Running/Succeeded
kube_pod_status_phase{phase!~"Running|Succeeded"} == 1

# Container restarts in the last hour
increase(kube_pod_container_status_restarts_total[1h]) > 0

# Pods stuck not ready
kube_pod_status_ready{condition="true"} == 0

# Per-namespace memory working set
sum by (namespace) (container_memory_working_set_bytes{container!=""})

# PVC fill % (alert when high)
100 * kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

## Checking scrape targets

A down target means a missing exporter or broken ServiceMonitor — a common cause of "no metrics".

```bash
# Targets that are NOT up
curl -s http://localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | select(.health!="up") | "\(.labels.job) \(.scrapeUrl) -> \(.lastError)"'

# Count up vs down
$S query 'count by (job) (up == 0)'   # jobs with at least one down target
```

## Notes

- Always start the port-forward before querying; `curl: connection refused` means it is not running.
- `promql.sh` uses `curl -sk -f` so a non-2xx response exits non-zero — check the port-forward first.
- For authoring PrometheusRules / ServiceMonitors, edit the manifests under
  `kubernetes/apps/observability/`; this skill only reads.
