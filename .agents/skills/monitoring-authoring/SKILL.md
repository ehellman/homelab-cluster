---
name: monitoring-authoring
description: |
  Authoring Prometheus monitoring resources (kube-prometheus-stack) in the homelab.

  Use when: (1) Creating or editing alert rules (PrometheusRule), (2) Adding recording rules,
  (3) Adding scrape targets via ServiceMonitor or PodMonitor, (4) Configuring Alertmanager
  routing with AlertmanagerConfig, (5) Adding monitoring for a new app or platform component,
  (6) Debugging why Prometheus is not discovering a monitor or rule.

  Triggers: "create alert", "add alerting", "PrometheusRule", "ServiceMonitor", "PodMonitor",
  "AlertmanagerConfig", "recording rule", "alert rule", "scrape target", "add monitoring",
  "prometheus not scraping", "monitor not discovered", "severity", "for duration"
user-invocable: false
---

# Monitoring Resource Authoring

Stack: `kube-prometheus-stack` HelmRelease (v86.2.0) in namespace `observability`. This skill
covers **creating and editing** monitoring CRs. This repo has NO flagger/Canary/canary-checker —
do not author any of those.

## Cluster-wide Discovery (the key fact)

Prometheus in this repo is configured with all selector-nil flags `false`:

```yaml
ruleSelectorNilUsesHelmValues: false
serviceMonitorSelectorNilUsesHelmValues: false
podMonitorSelectorNilUsesHelmValues: false
probeSelectorNilUsesHelmValues: false
scrapeConfigSelectorNilUsesHelmValues: false
```

With an empty selector, this means Prometheus discovers **every** PrometheusRule, ServiceMonitor,
PodMonitor, Probe, and ScrapeConfig in **any namespace, cluster-wide**. Consequences:

- A new monitor/rule just needs to **exist** in the cluster and be syntactically valid.
- **No `release: kube-prometheus-stack` label is required** (unlike upstream chart defaults). Do
  not add it; it does nothing here.
- CNPG clusters set `enablePodMonitor: true` in their spec — the operator emits a PodMonitor that
  Prometheus picks up automatically. Do not hand-author monitors for CNPG.

## Resource Types

| Resource | API Group |-|
|-|-|-|
| `PrometheusRule` | `monitoring.coreos.com/v1` | Alert + recording rules |
| `ServiceMonitor` | `monitoring.coreos.com/v1` | Scrape a Service's endpoints |
| `PodMonitor` | `monitoring.coreos.com/v1` | Scrape pods directly (no Service) |
| `AlertmanagerConfig` | `monitoring.coreos.com/v1alpha1` | Routing / receivers |

## File Placement

Resources live in the **owning app's** dir: `kubernetes/apps/<ns>/<app>/app/`, and are listed
in that dir's `kustomization.yaml`. The Flux Kustomization (`ks.yaml`) sets `targetNamespace`, so
monitors **omit `metadata.namespace`** — they inherit the app's namespace. Match the existing
convention (see `kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml`).

```yaml
# kubernetes/apps/<ns>/<app>/app/kustomization.yaml
resources:
  - ./helmrelease.yaml
  - ./servicemonitor.yaml   # add the new file here
  - ./prometheusrule.yaml
```

## PrometheusRule

Severity and `for` conventions:

| severity | typical `for` | use case |
|-|-|-|
| `critical` | 2m–5m | service down, data-loss risk |
| `warning` | 5m–15m | degraded, approaching limits |
| `info` | 10m–30m | informational, non-urgent |

`for: 0m` only for instant failures (e.g. SMART fail). Default 5m. Use 10m–15m for flap-prone
metrics (error rates, latency). Group related rules under named groups (`name:` ordering shows in
the Prometheus UI). Recording rules use `level:metric:operation` naming, e.g.
`app:http_requests:rate5m`.

Concrete example (`kubernetes/apps/observability/grafana/app/prometheusrule.yaml`):

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/monitoring.coreos.com/prometheusrule_v1.json
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: grafana
spec:
  groups:
    - name: grafana.rules
      rules:
        - alert: GrafanaDown
          expr: up{job="grafana", namespace="observability"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Grafana is down in {{ $labels.namespace }}"
            description: >-
              Grafana target {{ $labels.instance }} has been unreachable for
              5m. Dashboards and alerting UI are unavailable.
        - alert: GrafanaHighErrorRate
          expr: |
            sum(rate(grafana_http_request_duration_seconds_count{code=~"5.."}[5m]))
            /
            sum(rate(grafana_http_request_duration_seconds_count[5m]))
            > 0.05
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Grafana 5xx error rate above 5%"
            description: "Error rate is {{ $value | humanizePercentage }}."
        # recording rule
        - record: grafana:http_requests:rate5m
          expr: sum(rate(grafana_http_request_duration_seconds_count[5m]))
```

Annotation template functions: `{{ $value | humanize }}`, `humanizePercentage` (input 0–1),
`humanizeDuration` (seconds), `{{ $labels.<name> }}`.

## ServiceMonitor

Scrapes Services. The `selector.matchLabels` must match the target **Service's** labels, and the
endpoint `port` must be a **named** port on that Service. Omit `namespaceSelector` to scrape the
monitor's own namespace.

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/monitoring.coreos.com/servicemonitor_v1.json
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: grafana
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana
  endpoints:
    - port: http-metrics
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

## PodMonitor

Use when pods expose metrics with no Service (DaemonSets, sidecars). Use `podMetricsEndpoints`
instead of `endpoints`. Numeric (unnamed) ports must be quoted: `port: "15020"`. See the real
example at `kubernetes/apps/network/envoy-gateway/app/podmonitor.yaml`.

## AlertmanagerConfig

Routes/receivers scoped to alerts in the config's namespace. Place alongside the owning app.

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/monitoring.coreos.com/alertmanagerconfig_v1alpha1.json
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: grafana
spec:
  route:
    groupBy: ["alertname"]
    receiver: discord
    matchers:
      - name: namespace
        value: observability
  receivers:
    - name: discord
```

## Workflow

1. Prefer chart-native monitoring: check if the HelmRelease values expose `serviceMonitor.enabled`
   or `metrics.enabled` and turn it on rather than hand-authoring.
2. Otherwise create the CR in `kubernetes/apps/<ns>/<app>/app/`, add the schema header, omit
   `metadata.namespace`.
3. Register the file in that dir's `kustomization.yaml`.
4. Validate: `task template:validate-kubernetes-config` (kubeconform).
5. Apply: `task reconcile`.
6. Verify discovery:

```bash
kubectl get prometheusrule,servicemonitor,podmonitor -A
# rules loaded:
kubectl -n observability exec sts/prometheus-kube-prometheus-stack -c prometheus -- \
  wget -qO- localhost:9090/api/v1/rules | jq '.data.groups[].name'
# targets scraped:
kubectl -n observability exec sts/prometheus-kube-prometheus-stack -c prometheus -- \
  wget -qO- localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job'
```

## Common Mistakes

| Mistake | Impact | Fix |
|-|-|-|
| Adding `release: kube-prometheus-stack` label | Harmless noise; implies it's required | Omit it — discovery is cluster-wide |
| Hardcoding `metadata.namespace` | Conflicts with `targetNamespace` | Omit it; ks.yaml sets the namespace |
| ServiceMonitor selector misses the Service | No scrape, no error | `kubectl get svc -n <ns> --show-labels` and match |
| Endpoint `port` is a number, not the Service's port name | No scrape | Use the named port, or quote numeric in PodMonitor |
| Hand-authoring a CNPG monitor | Duplicate | CNPG `enablePodMonitor: true` already emits one |
| Alert on a non-existent metric | Stuck pending | Confirm the metric exists in Prometheus first |
| Forgetting to add file to `kustomization.yaml` | CR never applied | Add it under `resources:` |
