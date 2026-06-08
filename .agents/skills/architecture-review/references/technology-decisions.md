# Technology Decisions — Current Stack

The WHY behind each major choice in this homelab, and **when to deviate**. The
designer agent cites these when evaluating proposals so "stack fit" checks are
concrete. If a proposal duplicates a row below, default to reusing the existing
tool unless there is a documented reason.

| Layer | Choice | When to deviate |
|-|-|-|
| OS | Talos Linux | Never on a whim — immutable, API-driven, no SSH. New nodes get the same machine config. |
| GitOps | Flux | All workloads via `kubernetes/apps/<ns>/<app>/ks.yaml` + `app/` + HelmRelease. No `kubectl apply`. |
| CNI / network policy | Cilium (+ Hubble) | Default CNI. Use CiliumNetworkPolicy for segmentation; Hubble for flow visibility. |
| Ingress | Envoy Gateway (Gateway API) | `envoy-internal` (LAN) or `envoy-external` (public), `${SECRET_DOMAIN}`, cert-manager TLS. No second ingress controller. |
| Database | CloudNative-PG (ns `database`) | Postgres need → CNPG Cluster. Other engines only when Postgres genuinely cannot serve. |
| Storage | Rook-Ceph, class `ceph-block` | Default RWO block storage. NFS via `truenas-nfs` for shared/bulk media. |
| Monitoring | kube-prometheus-stack + standalone Grafana (ns `observability`) | Every app ships ServiceMonitor/PodMonitor + PrometheusRule. |
| Logs | Loki — **PLANNED, not deployed** | Do not assume log aggregation exists. Propose Loki explicitly if a design needs it. |
| Secrets (apps) | external-secrets + 1Password Connect (`onepassword-connect` ClusterSecretStore) | App credentials → ExternalSecret. Never commit plaintext secrets. |
| Secrets (bootstrap) | SOPS-age | Talos config and bootstrap-time secrets only. Not for runtime app secrets. |
| App packaging | bjw-s `app-template` (`oci://ghcr.io/bjw-s-labs/helm/app-template`) or native chart | Prefer app-template for simple apps; native chart when the upstream chart is mature. |
| Versions / updates | Renovate, inline annotations | Every image/chart version pinned and annotated. See the `versions-renovate` skill. |
| MCP | flux-operator-mcp (read-only) | For inspecting Flux/cluster state. Read-only — not a mutation path. |

---

## Talos Linux (over Ubuntu/Debian)

Immutable, API-driven Kubernetes OS. No SSH, no shell, no package manager — zero
config drift, minimal attack surface, everything declarative in machine configs.
Upgrades flow through the same declarative pipeline.

**Deviate when**: essentially never for the OS itself.

## Flux (over ArgoCD)

CRD-native GitOps. Reconciles git → cluster headlessly, no UI to tempt manual ops.
Layout is `kubernetes/apps/<namespace>/<app>/` with a `ks.yaml` (Flux Kustomization)
pointing at `app/`, which holds the HelmRelease and supporting manifests.

**Deviate when**: never — all workloads go through Flux.

## Cilium + Hubble (over Calico/Flannel)

eBPF CNI: kernel-level networking, L3/L4/L7 CiliumNetworkPolicy, Hubble flow
observability, default-deny posture available.

**Deviate when**: never for the CNI. New apps that accept traffic should ship a
CiliumNetworkPolicy scoping allowed flows.

## Envoy Gateway (Gateway API)

Ingress via the Gateway API, not legacy Ingress objects. Two gateways:
`envoy-internal` for LAN-only, `envoy-external` for internet-exposed routes.
Hostnames under `${SECRET_DOMAIN}`, TLS issued by cert-manager.

**Deviate when**: do not add a second ingress controller (no nginx/Traefik). Pick
the right gateway for the exposure level instead.

## CloudNative-PG (over bare Postgres / other operators)

Kubernetes-native Postgres operator in the `database` namespace: HA with failover,
WAL/base backups, declarative lifecycle via CRDs.

**Deviate when**: only if the workload needs a non-Postgres engine that CNPG
cannot provide. Default any relational need to a CNPG Cluster.

## Rook-Ceph (storage class `ceph-block`)

Distributed block storage; `ceph-block` is the default StorageClass for RWO PVCs.
Bulk/shared media uses the `truenas-nfs` NFS class instead.

**Deviate when**: large sequential/shared data that fits NFS better → `truenas-nfs`.
Otherwise use `ceph-block`.

## kube-prometheus-stack + Grafana (ns `observability`)

Prometheus + Alertmanager + a standalone Grafana. Monitoring is a day-1
requirement: every app ships a ServiceMonitor or PodMonitor plus PrometheusRule
alerts. **Loki is planned but NOT yet deployed** — do not design against centralized
log aggregation; if a proposal needs it, call out adding Loki as part of the work.

**Deviate when**: never skip monitoring "for now".

## external-secrets + 1Password Connect (app secrets)

App credentials are stored in 1Password and pulled at runtime via the
`onepassword-connect` ClusterSecretStore. Only the ExternalSecret CR lives in git;
the secret value never does.

**Deviate when**: bootstrap-time secrets (Talos, things needed before
external-secrets runs) use SOPS-age. Never commit plaintext secrets.

## SOPS-age (bootstrap secrets)

Age-encrypted secrets for Talos and bootstrap, decrypted by Flux's
kustomize-controller via the `sops-age` secret. See the `sops-age` skill for the
`.sops.yaml` rules.

**Deviate when**: runtime app secrets belong in external-secrets, not SOPS.

## bjw-s app-template (or native charts)

Most simple apps deploy via the bjw-s `app-template` OCI chart for a consistent
controller/service/ingress shape. Mature upstream charts are used directly when
they offer more than app-template would.

**Deviate when**: the upstream native chart is well-maintained and provides
features app-template can't model cleanly.

## Renovate (version management)

Every chart and image version is pinned and carries an inline `# renovate:`
annotation so updates arrive as reviewable PRs. See the `versions-renovate` skill
for annotation syntax and datasource rules.

**Deviate when**: never — un-pinned or hand-bumped versions are an anti-pattern.
