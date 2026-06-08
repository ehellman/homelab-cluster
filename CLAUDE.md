# Homelab Cluster — Claude Reference

A single-cluster, self-hosted Kubernetes homelab on **Talos Linux**, managed
declaratively with **Flux** GitOps. `main` is the desired state; the cluster
converges from git.

# Repository Structure

```
kubernetes/
  ├── apps/         # Flux-managed workloads, one dir per app
  │     └── <namespace>/<app>/
  │           ├── ks.yaml      # Flux Kustomization (targetNamespace, dependsOn, substituteFrom)
  │           └── app/         # HelmRelease, ExternalSecret, HTTPRoute, kustomization.yaml
  ├── components/   # Shared/reused Kustomize components
  └── flux/         # Flux bootstrap + cluster-wide config (sops decryption set here)
talos/              # Talos machine config (talhelper); SOPS full-encrypted
bootstrap/          # Initial cluster bootstrap
terraform/          # Out-of-cluster infrastructure
.agents/skills/     # Project skills (symlinked into .claude/skills/)
.claude/            # Agents, commands, settings
```

# Stack

- **OS:** Talos Linux (immutable). **GitOps:** Flux.
- **CNI / network policy:** Cilium (+ Hubble). **Ingress:** Envoy Gateway
  (Gateway API) — gateways `envoy-internal` / `envoy-external`, hostnames under
  `${SECRET_DOMAIN}`, TLS via cert-manager.
- **Database:** CloudNative-PG (namespace `database`). **Storage:** Rook-Ceph
  (`ceph-block`).
- **Monitoring:** kube-prometheus-stack + standalone Grafana (namespace
  `observability`). **Loki is planned, not yet deployed** — use `kubectl logs`.
- **Secrets:** external-secrets + 1Password Connect (ClusterSecretStore
  `onepassword-connect`) for app secrets; **SOPS-age** for Talos/bootstrap.
- **App packaging:** bjw-s `app-template` (OCI) or native charts.
- **Updates:** Renovate (inline `# renovate:` annotations).
- **Tooling:** `task` (go-task) via `mise`; read-only `flux-operator-mcp` MCP.

# Principles

- **GitOps-driven** — git is the source of truth; if it's not in git, it doesn't exist.
- **Declarative** — no manual operations; no `kubectl apply`, no UI edits, no SSH fixes.
- **Drift is a bug**, not an acceptable state.
- **Reproducible** — rebuildable from scratch; idempotent processes.
- **Self-healing** — prefer automation and convergence over manual intervention.
- **Observable** — new workloads ship with monitoring.
- **DRY** — compose; do not copy.

# Operating Rule

If uncertain: stop, identify the ambiguity, ask the user. **Correctness > speed.**

# Hard Constraints

**Secrets**
- NEVER commit plaintext secrets — use external-secrets (1Password) or SOPS-age.
- NEVER commit generated artifacts or caches.

**Cluster safety (single cluster — treat it as production)**
- NEVER mutate the cluster directly: no `kubectl apply/edit/patch/delete`, no
  `flux suspend/resume` as a "fix". Changes flow through git and Flux.
- Read-only investigation is fine (`kubectl get/describe/logs`, `flux get`,
  `flux-operator-mcp`).
- Do not use unsafe flags (`--force`, `--grace-period=0`).

**Git**
- No direct commits to `main`; always branch → PR.
- No force-push or history rewriting.
- PRs target **`ehellman/homelab-cluster`** (the fork), not upstream.

**Verification**
- Before committing manifests, validate: `task template:validate-kubernetes-config`
  (kubeconform) and `task template:validate-schemas` (CUE). Re-encrypt any changed
  `*.sops.yaml` with `task template:encrypt-secrets`.
- Never guess values — verify from source. Never ignore validation failures.

# Skills & Agents

Project skills live in `.agents/skills/` (symlinked into `.claude/skills/`) and
auto-load by trigger. Each has a `tests.yaml` of behavioral probes; run them with
the `instruction-eval` skill, and keep docs honest with `sync-claude`. Capture
durable corrections with `self-improvement`.

Four delegating commands wrap specialized agents:

| Command | Agent | Posture |
|-|-|-|
| `/design` | designer (opus, plan) | read-only architecture decisions |
| `/implement` | implementer (sonnet) | GitOps changes via branch → PR |
| `/troubleshoot` | troubleshooter (sonnet) | read-only diagnosis |
| `/security-test` | security-tester (opus) | read-only, non-destructive testing |
