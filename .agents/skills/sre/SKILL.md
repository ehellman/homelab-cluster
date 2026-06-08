---
name: sre
description: |
  SRE debugging methodology for this homelab's single Kubernetes cluster — incident triage,
  multi-source data collection, root cause analysis, and GitOps remediation recommendations.

  Use when: (1) Pods not starting, stuck, or failing (CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending),
  (2) Debugging Kubernetes errors or "why is my pod...", (3) Service degradation or unavailability,
  (4) Root cause analysis for any cluster incident, (5) Network traffic blocked by Cilium policy,
  (6) A failing Flux Kustomization or HelmRelease, (7) An ExternalSecret not syncing,
  (8) PVC stuck Pending or cert-manager TLS not issued.

  Triggers: "pod not starting", "pod stuck", "CrashLoopBackOff", "ImagePullBackOff", "OOMKilled",
  "Pending pod", "why is my pod", "kubernetes error", "k8s error", "service not available",
  "can't reach service", "debug kubernetes", "troubleshoot k8s", "what's wrong with my pod",
  "deployment not working", "helmrelease not ready", "flux not reconciling", "kustomization stuck",
  "externalsecret not syncing", "SecretSyncedError", "root cause", "5 whys", "incident",
  "network policy blocking", "hubble dropped", "stalled helmrelease", "PVC pending", "TLS not issued",
  "certificate not ready"
user-invocable: false
---

# Debugging Cluster Incidents

This is a **single** Kubernetes cluster. There is no dev/integration/live split and no promotion
pipeline — every fix lands in one place: this Git repo, reconciled by Flux.

## Read-Only Posture (CRITICAL)

This skill **investigates only**. NEVER mutate the cluster: no `kubectl apply`, `delete`, `patch`,
`edit`, `scale`, `cordon`, `label`, or `flux suspend/resume` as a fix. All collection commands are
read-only (`get`, `describe`, `logs`, `events`, `top`).

Fixes are GitOps changes: edit manifests under `kubernetes/`, commit, let Flux reconcile. Hand the
actual change to the relevant authoring skill:
- Postgres / CNPG Cluster → `cnpg-database`
- Alerts, ServiceMonitor, PrometheusRule → `monitoring-authoring`
- Cilium network policy → `cilium-expert`
- Secrets / SOPS → `sops-age`

## Core Principles

- **5 Whys** — NEVER stop at symptoms. Ask "why" until you reach the root cause.
- **Multi-Source Correlation** — Combine events, logs, Flux status, and metrics for a full picture.
- **Recommend, don't mutate** — Conclude with a GitOps remediation the user applies via Git.

## The 5 Whys (CRITICAL)

Apply 5 Whys before concluding. Stopping at symptoms leads to ineffective fixes.

```
Symptom: app pod in CrashLoopBackOff

Why #1: container exits non-zero on startup
Why #2: it can't read DB_PASSWORD from its env Secret
Why #3: the Secret doesn't exist
Why #4: the ExternalSecret is in SecretSyncedError
Why #5: the 1Password item key was renamed and no longer matches remoteRef.property

ROOT CAUSE: ExternalSecret remoteRef.property drifted from the 1Password item
FIX (GitOps): correct remoteRef in the ExternalSecret manifest, commit, let Flux reconcile
```

Red flags you haven't reached root cause: your "fix" raises a timeout/retry, addresses the
symptom not the cause, or you can still ask "but why did THAT happen?". See
[investigation-guide.md](investigation-guide.md).

## Tools Available

| Tool | Use for |
|-|-|
| `kubectl` | pod status, describe, events, logs (read-only verbs only) |
| `flux` CLI | `flux get kustomizations -A`, `flux get helmreleases -A`, `flux get sources -A` |
| `flux-operator-mcp` (MCP, read-only) | inspect Flux Kustomizations/HelmReleases/sources/events without shelling out |
| Cilium + Hubble | network-policy / connectivity path debugging |
| kube-prometheus-stack | metrics and firing alerts — see the `prometheus` skill |
| `kubectl logs` | log search (Loki is **planned**, not deployed — no log aggregation yet) |

## Investigation Phases

**Phase 1 — Triage:** Assess severity (P1 down / P2 degraded / P3 minor) and scope (one app vs
platform-wide). Most incidents here are a failing Flux Kustomization, a not-ready HelmRelease, or
a not-synced ExternalSecret — check those first.

**Phase 2 — Data Collection:** Run `scripts/cluster-health.sh [namespace]` for a read-only snapshot.
For targeted collection:

```bash
# GitOps reconciliation state (start here for most incidents)
flux get kustomizations -A
flux get helmreleases -A
flux get sources all -A

# Pod status, events, logs
kubectl get pods -n <namespace>
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --tail=100
kubectl logs <pod> -n <namespace> --previous

# Event timeline
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Resource usage
kubectl top pods -n <namespace>
```

The `flux-operator-mcp` MCP server can return Kustomization/HelmRelease status, inventories, and
events directly — prefer it over shelling out when only Flux state is needed.

For metrics and firing alerts, use the `prometheus` skill (port-forwards to in-cluster Prometheus).

**Phase 3 — Correlation:** Extract timestamps from events, logs, and Flux conditions → identify
what happened FIRST → trace the cascade. A failing Kustomization upstream usually explains
downstream pod failures.

**Phase 4 — Root Cause:** Apply 5 Whys. Validate: temporal (before the symptom?), causal (logically
explains it?), evidence (supporting data?), complete (asked "why" enough times?).

**Phase 5 — Remediation (GitOps only):** Recommend the change; do not apply it. State:
- **Root cause** — the one declarative thing that drifted or is misconfigured
- **The fix** — which manifest under `kubernetes/` to edit, and which authoring skill owns it
- **Prevention** — an alert (`monitoring-authoring`), a `dependsOn`, or a resource limit

For symptom → first check → common cause mapping, see [investigation-guide.md](investigation-guide.md).

## Key Namespaces

| Namespace | Runs | Failure shows up as |
|-|-|
| `flux-system` | Flux controllers, Kustomizations, HelmReleases | reconcile errors, stalled releases |
| `kube-system` | Cilium (CNI), Hubble | dropped traffic, DNS failures |
| `network` | envoy-gateway | 503s, route not programmed |
| `observability` | kube-prometheus-stack, grafana | missing metrics, alerts |
| `database` | cloudnative-pg | CNPG cluster degraded, PVC pending |
| `external-secrets` | onepassword-connect, ESO | ExternalSecret SecretSyncedError |

## Network Policy Debugging (Cilium + Hubble)

Cilium enforces policy and Hubble observes flows. Blocked traffic is usually a missing/incorrect
policy or label.

```bash
# Hubble relay access (run once per session)
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Dropped traffic in a namespace
hubble observe --verdict DROPPED --namespace <namespace> --since 5m

# A specific flow
hubble observe --from-namespace <source> --to-namespace <dest> --since 5m
```

Hand the policy change itself to the `cilium-expert` skill. Do not edit policy live.

## Keywords

kubernetes, debugging, crashloopbackoff, oomkilled, pending, imagepullbackoff, root cause analysis,
5 whys, incident investigation, flux kustomization, helmrelease not ready, externalsecret,
SecretSyncedError, cilium, hubble, dropped traffic, pvc pending, cert-manager, tls, read-only, gitops
