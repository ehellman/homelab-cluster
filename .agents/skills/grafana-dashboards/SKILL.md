---
name: grafana-dashboards
description: |
  Authoring and provisioning Grafana dashboards in this homelab via GitOps —
  vendor dashboards through Helm values, custom dashboards through sidecar ConfigMaps.

  Use when: (1) Adding a community/vendor dashboard (gnetId or JSON URL), (2) Authoring a
  custom dashboard from your own panels, (3) Wrapping dashboard JSON in a ConfigMap for the
  sidecar, (4) Choosing folders for dashboards, (5) Debugging a dashboard that won't appear
  in Grafana, (6) Discovering which metrics/PromQL to put on panels.

  Triggers: "grafana dashboard", "add dashboard", "create dashboard", "dashboard ConfigMap",
  "grafana_dashboard label", "grafana sidecar", "gnetId", "import dashboard", "dashboard folder",
  "dashboard not showing", "grafana folder annotation", "provision dashboard"
user-invocable: false
---

# Grafana Dashboard Provisioning

Grafana runs as its own HelmRelease (`grafana`, chart `10.5.15`) in the `observability`
namespace — **separate** from `kube-prometheus-stack`, where the bundled Grafana is disabled.
The only datasource is Prometheus at
`http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090` (uid `prometheus`).

There is **no Grafana MCP server** in this repo (`.mcp.json` only has read-only
`flux-operator-mcp`). The authoring workflow is **GitOps**: write JSON → wrap in a ConfigMap →
register in a `kustomization.yaml` → `task reconcile` → verify in the Grafana UI.

For panel layout, units, and threshold conventions see the `dashboard-design` skill.
For writing/testing the PromQL behind panels see the `prometheus` skill.

## Two provisioning methods

| Method | Use for | Defined in |
|-|-|-|
| Helm `dashboards` values | Vendor/community dashboards (gnetId or JSON URL) | `grafana/app/helmrelease.yaml` |
| Sidecar ConfigMap | Custom dashboards, app-owned dashboards | A `ConfigMap` near the owning app |

Decision: **someone else maintains the JSON** (grafana.com, an upstream repo) → Helm values.
**You maintain the JSON** → ConfigMap.

## Method 1 — Vendor dashboard via Helm values

Edit the `dashboards` block in `grafana/app/helmrelease.yaml`. Entries are grouped into the
folders declared by `dashboardProviders`: `default` (root), `kubernetes` (folder `Kubernetes`),
`flux` (folder `Flux`). Reference by grafana.com ID **or** raw JSON URL — always set the
datasource to `Prometheus`.

```yaml
dashboards:
  default:
    # https://grafana.com/grafana/dashboards/1860 — Node Exporter Full
    node-exporter-full:
      gnetId: 1860
      revision: 37
      datasource: Prometheus
  kubernetes:
    kubernetes-global:
      url: https://raw.githubusercontent.com/dotdc/grafana-dashboards-kubernetes/master/dashboards/k8s-views-global.json
      datasource: Prometheus
```

`gnetId` needs an explicit `revision`. Pin the revision/URL ref so reconciles are deterministic.

## Method 2 — Custom dashboard via sidecar ConfigMap

The sidecar (`sidecar.dashboards` in the HelmRelease) watches **all namespaces**
(`searchNamespace: ALL`) for ConfigMaps carrying the label key `grafana_dashboard`
(with an **empty value**). The folder comes from the `grafana_folder` annotation.

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-ceph-overview
  namespace: observability
  labels:
    grafana_dashboard: ""        # REQUIRED — label key only, empty value
  annotations:
    grafana_folder: "Storage"    # Grafana UI folder; created if absent
data:
  ceph-overview.json: |-
    {
      "uid": "ceph-overview",
      "title": "Ceph Overview",
      "schemaVersion": 39,
      "panels": [ ... ]
    }
```

Rules:
- Label is `grafana_dashboard: ""` — the **key** triggers the sidecar; the value is empty.
- One dashboard per ConfigMap; the data key (`<slug>.json`) should match the dashboard `uid`.
- Put the ConfigMap in the namespace of the app it monitors (the sidecar finds it anywhere).
- Embed JSON with `|-`. In panels, set `"datasource": { "type": "prometheus", "uid": "prometheus" }`
  — never a `${datasource}` template variable.

### Register and reconcile

Add the ConfigMap file to the owning app's `kustomization.yaml`:

```yaml
resources:
  - ./helmrelease.yaml
  - ./grafana-dashboard.yaml
```

Then push it through Flux and verify:

```bash
task reconcile                                # flux reconcile kustomization flux-system
kubectl -n observability get cm -l grafana_dashboard   # confirm the ConfigMap exists
kubectl -n observability logs deploy/grafana -c grafana-sc-dashboard | tail   # sidecar load log
```

Open Grafana, find the dashboard in its `grafana_folder`. Iterate by editing the JSON in git
and re-reconciling — sidecar-loaded dashboards are read-only in the UI by design.

## Discovering metrics

Never guess metric names. Port-forward Prometheus and query it before authoring panels:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# then browse http://localhost:9090 — use the metrics explorer / Graph tab
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | jq '.data[]' | grep ceph
curl -s --data-urlencode 'query=up{namespace="observability"}' http://localhost:9090/api/v1/query | jq
```

See the `prometheus` skill for PromQL patterns (rate, ratio, histogram_quantile).

## Validate

Before committing, validate the manifests:

```bash
task template:validate-kubernetes-config
```

Checklist:
- [ ] Custom dashboard ConfigMap has label `grafana_dashboard: ""` (empty value).
- [ ] Folder set via `grafana_folder` annotation (not a label).
- [ ] Panel datasource is `{ "type": "prometheus", "uid": "prometheus" }`, never `${datasource}`.
- [ ] Dashboard `uid` is unique and matches the `<slug>.json` data key.
- [ ] ConfigMap added to the owning app's `kustomization.yaml`.
- [ ] Vendor dashboards set `datasource: Prometheus` and pin `revision`/URL ref.
- [ ] `task template:validate-kubernetes-config` passes, then `task reconcile`.

## Debugging

| Symptom | Cause | Fix |
|-|-|-|
| Dashboard never appears | Missing/typo'd `grafana_dashboard` label | Add the bare label key, empty value |
| Lands in wrong/no folder | Missing `grafana_folder` annotation | Add the annotation (it is an annotation, not a label) |
| Panels blank "No data" | `${datasource}` template var | Hardcode `uid: "prometheus"` in each panel |
| ConfigMap ignored | Not in a kustomization `resources` list | Register it, then `task reconcile` |
| Vendor dashboard blank | Datasource not mapped | Set `datasource: Prometheus` in the values entry |
| Guessed metric names | Metric doesn't exist | Port-forward Prometheus and confirm names first |

Optional future enhancement: an `mcp-grafana` server would allow live push/screenshot
iteration. It is **not** configured here, so do not depend on it — author via GitOps.

## Keywords

Grafana, dashboard, ConfigMap, sidecar, grafana_dashboard, grafana_folder, gnetId, gnet,
provision, folder annotation, searchNamespace, observability, Prometheus datasource, GitOps,
task reconcile, vendor dashboard, custom dashboard, no MCP
