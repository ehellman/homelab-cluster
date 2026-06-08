# SRE Investigation Reference

Single cluster, GitOps via Flux. Every fix is a Git change, never a live mutation.

## Symptom → First Check → Common Cause

| Symptom | First Check | Common Cause |
|-|-|-|
| `CrashLoopBackOff` | `kubectl logs <pod> --previous` | App error, or missing Secret/ConfigMap it depends on |
| `ImagePullBackOff` | `kubectl describe pod` events | Wrong image/tag or registry auth |
| `OOMKilled` | `kubectl describe pod` (last state), limits | Memory leak or limits too low |
| `Pending` pod | Events, `kubectl get pvc -n <ns>`, node capacity | Unbound PVC or insufficient resources |
| HelmRelease not Ready | `flux get helmreleases -A`, `kubectl describe helmrelease` | Bad values, missing CRD, failing dependsOn, install timeout |
| Kustomization stuck | `flux get kustomizations -A`, `kubectl describe kustomization` | Build/apply error, missing source, dependency not ready, SOPS decrypt fail |
| ExternalSecret `SecretSyncedError` | `kubectl describe externalsecret -n <ns>` | 1Password item/key renamed, onepassword-connect down, wrong remoteRef |
| Service unreachable / 503 | Hubble dropped traffic + envoy-gateway route | Cilium policy blocking, or HTTPRoute not programmed |
| Can't reach Postgres | Hubble flow + CNPG cluster status | Policy blocking, or CNPG cluster degraded |
| PVC `Pending` (ceph-block) | `kubectl describe pvc`, Rook/Ceph health | StorageClass missing, Ceph OSD down, capacity exhausted |
| cert-manager TLS not issued | `kubectl describe certificate`, then certificaterequest/order/challenge | DNS-01/HTTP-01 challenge failing, wrong issuer, rate limit |

## Common Failure Chains

```
Secret:   ExternalSecret SecretSyncedError → Secret missing → pod CrashLoopBackOff
GitOps:   Kustomization apply error → resource never created → downstream pods Pending
Helm:     HelmRelease values error → release not Ready → workload absent
Storage:  Ceph unhealthy → PVC Pending → pod Pending → HelmRelease install timeout
Network:  Cilium policy gap → traffic DROPPED → upstream times out → 503 at gateway
TLS:      ACME challenge fails → Certificate not Ready → gateway serves no/stale cert
```

## Where to Look First, by Layer

| Layer | Read-only command |
|-|-|
| Flux reconciliation | `flux get kustomizations -A` then `flux get helmreleases -A` |
| Flux source | `flux get sources all -A` |
| Secrets | `kubectl get externalsecret -A` (look for non-`SecretSynced` status) |
| Network path | `hubble observe --verdict DROPPED --namespace <ns> --since 5m` |
| Storage | `kubectl get pvc -A` (anything not `Bound`) |
| Certificates | `kubectl get certificate -A` (anything not `True`/Ready) |
| Metrics / alerts | use the `prometheus` skill |

## 5 Whys: Red Flags You Haven't Reached Root Cause

- Your "fix" raises a timeout, retry count, or replica count
- Your "fix" addresses the symptom, not what caused it
- You can still ask "but why did THAT happen?"
- Multiple symptoms share one underlying cause you haven't named
- The fix is a live `kubectl`/`flux` command instead of a Git change

## Remediation Always Lands in Git

Hand the actual change to the owning skill, then commit and let Flux reconcile:

| Domain | Owning skill |
|-|-|
| Postgres / CNPG | `cnpg-database` |
| Alerts / monitors | `monitoring-authoring` |
| Cilium policy | `cilium-expert` |
| Secrets / SOPS | `sops-age` |
