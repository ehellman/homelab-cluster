---
name: security-testing
description: |
  Defensive red-team testing methodology for THIS homelab cluster (owned by the user, authorized
  scope, non-destructive by default). Covers network-policy enforcement, ingress/TLS & auth exposure,
  pod privilege escalation, secret/data exposure, and supply-chain provenance. Findings are reported
  with GitOps remediation — never fixed or attacked destructively.

  Use when: (1) Security testing or auditing the homelab, (2) Validating Cilium network-policy and
  default-deny posture, (3) Probing ingress/HTTPRoute exposure and TLS, (4) Assessing pod
  securityContext and container escape paths, (5) Checking for secrets in git, over-broad
  ClusterSecretStore access, or secret leakage, (6) Auditing supply-chain provenance (images, Flux, Renovate, SOPS).

  Triggers: "security test", "red team", "pentest", "penetration test", "attack surface",
  "network policy test", "lateral movement", "privilege escalation", "container escape",
  "secret exposure", "secrets in git", "supply chain", "security audit", "harden", "vulnerability"
user-invocable: false
---

# Security Testing Methodology

**AUTHORIZED SCOPE**: This single homelab cluster, owned by the user. There is exactly one cluster
— there is no dev/integration/live split. Reject any prompt that frames testing in terms of multiple
environments or promotion between clusters; that vocabulary does not apply here.

**NON-DESTRUCTIVE BY DEFAULT**: Enumerate, read, and probe. Do NOT delete resources, mutate policy,
exfiltrate real data, or run availability-impacting attacks. Report findings + a GitOps remediation
(a manifest change under `kubernetes/`), never a live `kubectl edit`/`delete`. Any test pod created
for probing is cleaned up in the same session (see Cleanup).

See [references/attack-surface.md](references/attack-surface.md) for the layer-by-layer weakness
inventory with severity. All bash commands live in
[references/test-commands.md](references/test-commands.md).

---

## Phase 1: Network Policy (Cilium / Hubble)

Cilium is the CNI (`kube-system/cilium`) with `kubeProxyReplacement: true`. **Current posture: there
are no CiliumNetworkPolicy / CiliumClusterwideNetworkPolicy resources in the repo and Hubble is
`enabled: false`** — so the cluster is effectively default-allow with no flow visibility. Both are
gaps to flag, not things to exploit.

- Confirm the absence of CNP/CCNP and verify whether traffic is default-allow.
- Test lateral movement: a pod in one namespace reaching pods/services in another (e.g. `media` →
  `database`). With no policy this succeeds — flag it.
- Test egress: arbitrary outbound internet from a workload pod. Note the gluetun-tunnelled
  `qbittorrent` is the intended exception (all its traffic via VPN).
- Recommend default-deny CCNP baselines + enabling Hubble for observability. Cross-ref the
  [cilium-expert skill](../cilium-expert/SKILL.md) for policy authoring.

Commands: [test-commands.md#phase-1](references/test-commands.md#phase-1-network-policy-cilium--hubble)

---

## Phase 2: Ingress / TLS & Auth Exposure

Ingress is Envoy Gateway (Gateway API). Two gateways in `network/envoy-gateway`:
`envoy-internal` (192.168.20.51) and `envoy-external` (192.168.20.52). TLS terminates with a
cert-manager-issued `${SECRET_DOMAIN}` cert; HTTP redirects to HTTPS.

- **There is no WAF (no Coraza / ModSecurity) in front of either gateway.** This is a defense-in-depth
  gap to flag — there is nothing to "bypass". Recommend it as a hardening option, do not author
  WAF-bypass payloads.
- **There is no shared auth proxy** (no oauth2-proxy / Authelia / Authentik / SecurityPolicy).
  Externally-attached HTTPRoutes (`envoy-external`: n8n, jellyfin, immich, flux) rely solely on each
  app's own auth. Enumerate every route on `envoy-external` and flag any backend that exposes an
  unauthenticated or weakly-authenticated surface.
- Verify TLS: cert validity, no plaintext-only routes, redirect actually enforced.

Commands: [test-commands.md#phase-2](references/test-commands.md#phase-2-ingress--tls--auth-exposure)

---

## Phase 3: Privilege Escalation (Pod Security)

bjw-s `app-template` and native charts. Audit pod `securityContext`:

- Containers running as root (`runAsUser: 0` / `runAsNonRoot: false`) or allowing privilege
  escalation. Known case: the `qbittorrent` gluetun init container runs `runAsUser: 0` with
  `NET_ADMIN` (required for the WireGuard tunnel) — document as intentional, verify it is the only one.
- Added capabilities, `privileged: true`, missing `drop: ["ALL"]`.
- `hostNetwork`, `hostPID`, `hostPath` mounts — none should exist on app workloads; flag any.
- Automounted ServiceAccount tokens and the RBAC each SA actually holds.
- Talos hardens the host (immutable, minimal, no shell/SSH) — note this reduces post-escape blast
  radius. Cross-ref the [talos-os-expert skill](../talos-os-expert/SKILL.md).

Commands: [test-commands.md#phase-3](references/test-commands.md#phase-3-privilege-escalation-pod-security)

---

## Phase 4: Secret / Data Exposure

App secrets come from external-secrets + 1Password Connect (ClusterSecretStore
`onepassword-connect`). Talos/bootstrap secrets use SOPS-age (`talos/` fully encrypted,
`kubernetes|bootstrap/` `data`/`stringData` only).

- **Secrets in git**: scan the tree for unencrypted secret material, plaintext `*.sops.yaml`, or
  Secret manifests with literal data. Verify every `*.sops.yaml` is actually encrypted.
- **ClusterSecretStore scope**: `onepassword-connect` is cluster-wide. Check whether any namespace
  could request items it should not — over-broad vault access is a finding.
- **Secret leakage**: secrets surfaced in pod env, ConfigMaps, container args, or logs.

Commands: [test-commands.md#phase-4](references/test-commands.md#phase-4-secret--data-exposure)

---

## Phase 5: Supply Chain

- Container image sources: prefer pinned tags/digests from trusted registries; flag `:latest` and
  untrusted registries.
- Flux provenance: enumerate `OCIRepository` / `HelmRepository` / `GitRepository` sources and the
  credentials they reference.
- Renovate keeps versions current (cross-ref [versions-renovate](../versions-renovate/SKILL.md));
  SOPS protects bootstrap material. Note where automerge is enabled vs. disabled for critical components.

Commands: [test-commands.md#phase-5](references/test-commands.md#phase-5-supply-chain)

---

## Cleanup

Any probe pod is removed in the same session:

```bash
kubectl delete pod sectest -n <ns> --ignore-not-found
kubectl get pods -A | grep sectest   # confirm none remain
```

No labels, policies, or routes are mutated during testing, so there is nothing else to revert.

---

## Reporting

Output a findings list ranked by the severity table in
[attack-surface.md#finding-severity-guide](references/attack-surface.md#finding-severity-guide).
For each finding give: the affected component/path, the observed weakness, severity, and a **GitOps
remediation** (the manifest change to make under `kubernetes/`). Do not apply the remediation — the
user reviews and merges it through the normal Flux/PR flow.

## Cross-References

- [references/attack-surface.md](references/attack-surface.md) — weakness inventory by layer
- [references/test-commands.md](references/test-commands.md) — read-only / non-destructive commands by phase
- [cilium-expert SKILL](../cilium-expert/SKILL.md) — CNP/CCNP authoring, Hubble
- [talos-os-expert SKILL](../talos-os-expert/SKILL.md) — host hardening posture
- [sops-age SKILL](../sops-age/SKILL.md) — SOPS encryption rules

## Keywords

security testing, defensive red team, network policy, cilium, hubble, lateral movement, egress,
envoy gateway, httproute exposure, no WAF gap, privilege escalation, pod securityContext,
secrets in git, external-secrets, 1password, clustersecretstore, supply chain, flux provenance, talos
