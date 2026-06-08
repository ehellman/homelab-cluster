# Homelab Attack Surface Inventory

Weaknesses and observation points for THIS single homelab cluster (owned by the user, authorized,
non-destructive scope). Each entry notes whether it is an accepted/intentional design or a gap to
flag, plus exploitation potential and severity. There is no dev/integration/live split — every entry
is about the one cluster.

---

## Network Layer (Cilium)

### NET-001: No CiliumNetworkPolicy / CCNP — default-allow

**Component**: Cilium CNI (`kubernetes/apps/kube-system/cilium`)

No `CiliumNetworkPolicy` or `CiliumClusterwideNetworkPolicy` resources exist in the repo. Pod-to-pod
and egress traffic is unrestricted.

- **Exploitation**: A compromised pod moves laterally to any namespace/service and egresses freely.
- **Remediation**: Author default-deny CCNP baselines + per-app allow policies (cilium-expert skill).
- **Severity**: High (no segmentation)

### NET-002: Hubble disabled — no flow visibility

**Component**: Cilium Helm values (`hubble.enabled: false`)

Flow observability and the Hubble UI/relay are off, so lateral movement and policy violations are
unobserved.

- **Exploitation**: Reconnaissance and lateral movement go undetected.
- **Remediation**: Enable Hubble (relay + metrics) once policies exist.
- **Severity**: Medium

### NET-003: DNS / egress always available

**Component**: CoreDNS + unrestricted egress (no policy)

Every pod resolves DNS and reaches the internet. Until egress policy exists this is an exfiltration path.

- **Note**: `qbittorrent` egress is intentionally tunnelled through gluetun (VPN); that is the design.
- **Severity**: Low (folds into NET-001 once default-deny lands)

---

## Gateway / Ingress Layer (Envoy Gateway)

### GW-001: No WAF in front of either gateway — GAP, not a bypass

**Component**: `envoy-external` (192.168.20.52) / `envoy-internal` (192.168.20.51)

There is no Coraza / ModSecurity / WAF layer. There is nothing to bypass — the absence itself is the
finding.

- **Remediation**: Optionally add a WAF (e.g. Coraza WasmPlugin / EnvoyExtensionPolicy) for external routes.
- **Severity**: Informational / Low (defense-in-depth gap)

### GW-002: No shared auth proxy — apps self-authenticate

**Component**: HTTPRoutes (no oauth2-proxy / Authelia / SecurityPolicy present)

Externally-attached routes on `envoy-external` (n8n, jellyfin, immich, flux) rely only on each app's
own authentication. Any route exposing an unauthenticated admin/API surface is a finding.

- **Exploitation**: Reach an app's exposed surface directly over the external gateway.
- **Remediation**: Add an `EnvoyExtensionPolicy`/`SecurityPolicy` for external auth, or restrict the
  route to `envoy-internal`.
- **Severity**: Medium (per-route, depends on the backend)

### GW-003: TLS / redirect enforcement

**Component**: cert-manager `${SECRET_DOMAIN}` cert; HTTP→HTTPS redirect route

Verify the redirect is actually enforced and no route serves plaintext-only.

- **Severity**: Low (verification item)

---

## Container / Privilege Layer

### CTR-001: gluetun init container — root + NET_ADMIN

**Component**: `qbittorrent` gluetun init container (`runAsUser: 0`, `cap NET_ADMIN`)

Root with NET_ADMIN to build the WireGuard tunnel.

- **Design rationale**: WireGuard requires NET_ADMIN and root. Intentional.
- **Action**: Confirm it is the *only* privileged container; the qbittorrent app container drops ALL caps.
- **Severity**: Medium (intentional, scoped)

### CTR-002: Workload securityContext drift

**Component**: bjw-s app-template / native chart workloads

Flag any pod that runs as root, allows privilege escalation, adds capabilities, sets `privileged`,
or uses `hostNetwork` / `hostPID` / `hostPath`.

- **Severity**: High if found on an app workload, else N/A

### CTR-003: Talos host hardening (mitigating)

**Component**: Talos OS (immutable, minimal, no shell/SSH)

Reduces post-escape blast radius — note as a positive when scoring container findings.

- **Severity**: Informational

---

## Secret / Credential Layer

### CRED-001: Secrets committed to git

**Component**: repo tree, `*.sops.yaml`

Plaintext secret material, an unencrypted `*.sops.yaml`, or a Secret manifest with literal data.

- **Exploitation**: Direct credential theft from git history.
- **Remediation**: Encrypt via SOPS-age or move to external-secrets.
- **Severity**: Critical if found

### CRED-002: ClusterSecretStore over-broad access

**Component**: `onepassword-connect` ClusterSecretStore (cluster-wide)

A cluster-scoped store means any namespace's ExternalSecret can pull from the connected vault.

- **Remediation**: Scope vault access / consider namespaced SecretStores for sensitive items.
- **Severity**: Medium

### CRED-003: Secret leakage in env / logs

**Component**: pod env, ConfigMaps, container args, logs

Secrets surfaced as plaintext env or echoed to logs.

- **Severity**: Medium–High depending on the secret

---

## Supply Chain Layer

### SC-001: Image provenance

**Component**: container images across workloads

Unpinned `:latest` tags or untrusted registries.

- **Remediation**: Pin tags/digests, trusted registries, Renovate-tracked (versions-renovate skill).
- **Severity**: Medium

### SC-002: Flux source provenance

**Component**: `OCIRepository` / `HelmRepository` / `GitRepository` + their auth secrets

Enumerate sources and the credentials they reference; note automerge enabled vs. disabled for critical components.

- **Severity**: Medium

---

## Finding Severity Guide

| Severity | Criteria | Example |
|-|-|-|
| Critical | Credential theft, cluster takeover, RCE | secrets in git, container escape |
| High | Lateral movement, privilege escalation, cross-namespace access | no network policy, root app workload |
| Medium | Information disclosure, policy/auth gap with limited impact | over-broad ClusterSecretStore, unpinned images |
| Low | Minor defense-in-depth gap | DNS egress, no Hubble |
| Informational | Design observation / accepted risk | no WAF present, Talos hardening |
