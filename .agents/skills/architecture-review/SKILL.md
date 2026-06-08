---
name: architecture-review
description: |
  Design-evaluation framework for the homelab. Preloaded by the designer agent
  to ground proposed technology additions and architecture changes in the real
  current stack and established principles.

  Use when: (1) Proposing a new app or platform component, (2) Evaluating a technology
  addition, (3) Assessing stack fit / whether to reuse existing tooling, (4) Comparing
  implementation approaches, (5) Reviewing an architecture decision before it lands.

  Triggers: "architecture review", "evaluate technology", "stack fit", "should we use",
  "should we add", "technology comparison", "design review", "architecture decision",
  "propose adding", "new app", "what's the best way to deploy"
user-invocable: false
---

# Architecture Evaluation Framework

Score every proposed addition or change against the five criteria below, then
check it against the anti-patterns table. Cite the relevant stack decision from
[references/technology-decisions.md](references/technology-decisions.md) — that
file is the source of truth for what is already deployed and why.

## Core Principles

The homelab optimizes for these. A proposal that weakens one needs a strong reason.

- **GitOps source of truth**: every resource lives in git, reconciled by Flux. Nothing applied by hand.
- **Declarative**: desired state in YAML/HelmRelease, not imperative steps.
- **Reproducible**: the cluster can be rebuilt from the repo (Talos config + Flux).
- **Self-healing**: controllers/operators converge state; failures recover without manual toil.
- **Observable**: metrics scraped by Prometheus, dashboards in Grafana, alerts wired on day 1.

## Evaluation Criteria

### 1. Principle Alignment

Score each principle Strong / Neutral / Weak:
- Is it fully representable in git and deployed by Flux?
- Is the desired state declarative (HelmRelease, CRDs, app-template values)?
- Does it self-heal, or does it need manual babysitting?
- Is it observable from day 1 (ServiceMonitor/PodMonitor + PrometheusRule)?
- Does rebuild-from-repo still work after adding it?

### 2. Stack Fit

Always check first whether something already deployed solves the problem.
- Does this overlap an existing tool? (e.g. proposing a second ingress when Envoy Gateway exists; a second secrets backend when external-secrets + 1Password is in place; a second DB engine when CloudNative-PG covers Postgres).
- Does it integrate with the Flux layout (`kubernetes/apps/<ns>/<app>/ks.yaml` + `app/` + HelmRelease)?
- Does it run on bare-metal Talos? (no cloud-only managed services).
- Does it use the standard packaging (bjw-s `app-template` or a native chart) and Renovate-tracked versions?
- Storage → `ceph-block` (Rook-Ceph). Ingress → `envoy-internal` / `envoy-external`, `${SECRET_DOMAIN}`, cert-manager TLS. Network policy → Cilium.

### 3. Operational Cost

- How is it monitored? Must integrate with kube-prometheus-stack (ServiceMonitor/PodMonitor + alerts).
- How is it backed up / recovered? Stateful workloads need a recovery story.
- How does it upgrade? Declarative, version pinned, tracked by Renovate.
- Blast radius when it fails? Isolated namespace beats cluster-wide.

### 4. Complexity Budget

- Could an existing component solve this with less moving parts?
- What is the 12-month maintenance burden (CRD churn, upstream breakage, manual steps)?
- Does the complexity buy proportional value, or is it gold-plating?

### 5. Alternatives Considered

- Which already-deployed components could cover this? (check `technology-decisions.md` first).
- What are the top 2-3 ecosystem alternatives, and why this one?
- How do comparable homelabs solve it? (use the `kubesearch` skill for real configs).

## Anti-Patterns to Challenge

| Anti-pattern | Why it's wrong | Correct approach |
|-|-|-|
| "Just run a container" with no monitoring | Invisible failures, no alerting | ServiceMonitor/PodMonitor + PrometheusRule from day 1 |
| New app with no secrets wiring | Hardcoded creds or none at all | ExternalSecret via `onepassword-connect` ClusterSecretStore |
| New app with no network policy | Flat network, no segmentation | CiliumNetworkPolicy scoped to required flows |
| Adding a tool that duplicates an existing one | Stack bloat, double maintenance | Reuse the deployed tool (see stack fit) |
| Cloud-only managed service for a self-hostable need | Breaks self-hosted/bare-metal model, vendor lock-in | Self-host on the cluster (CNPG, Rook-Ceph, etc.) |
| Single instance where HA is cheap | Avoidable single point of failure | Run replicas, or document the recovery procedure |
| Assuming Loki/log aggregation exists | Loki is planned, not deployed | Don't depend on it; propose it explicitly if needed |
| Hand-applied or un-pinned versions | Drift, no audit trail, no updates | HelmRelease in git, version pinned, Renovate annotation |

## Output Shape

When reviewing, return: a per-criterion Strong/Neutral/Weak verdict, any anti-patterns
triggered, the closest existing stack component, and a clear recommend / revise / reject
with the reason tied to a principle or a stack decision.
