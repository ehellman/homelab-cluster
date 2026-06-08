# Security Testing Commands

Read-only / non-destructive probes for the single homelab cluster. Default `kubectl` context (one
cluster — no `--context dev`). Nothing here deletes, mutates policy, or exfiltrates real data. Any
`sectest` probe pod is removed in the Cleanup step.

---

## Phase 1: Network Policy (Cilium / Hubble)

```bash
# Confirm the current posture: are there any policies at all?
kubectl get ciliumnetworkpolicies,ciliumclusterwidenetworkpolicies -A
# Expect: "No resources found" — default-allow. Flag as NET-001.

# Hubble status (expect disabled — NET-002)
kubectl -n kube-system get pods -l k8s-app=hubble-relay
```

```bash
# Lateral movement: a media pod reaching another namespace's service (expect success = finding)
kubectl run sectest --image=nicolaka/netshoot -n media --restart=Never -- sleep 1800
kubectl exec -n media sectest -- curl -s --connect-timeout 3 -o /dev/null -w '%{http_code}\n' \
  http://<service>.database.svc.cluster.local:<port>

# Egress: arbitrary outbound internet (expect success on non-gluetun pods = finding)
kubectl exec -n media sectest -- curl -s --connect-timeout 3 https://example.com -o /dev/null -w '%{http_code}\n'
```

---

## Phase 2: Ingress / TLS & Auth Exposure

```bash
# Enumerate gateways and their VIPs
kubectl get gateway -A -o wide

# Every route attached to the EXTERNAL gateway — each backend self-authenticates (GW-002)
kubectl get httproute -A -o json | jq -r \
  '.items[] | select(.spec.parentRefs[].name=="envoy-external") |
   "\(.metadata.namespace)/\(.metadata.name) -> \(.spec.hostnames)"'

# Confirm there is NO WAF / auth filter (expect empty = GW-001 / GW-002 gaps)
kubectl get wasmplugins,securitypolicies,envoyextensionpolicies -A 2>/dev/null

# TLS + redirect verification (read-only HEAD)
EXT=192.168.20.52
curl -sk --resolve "<host>:443:${EXT}" -I "https://<host>/"
curl -s  --resolve "<host>:80:${EXT}"  -I "http://<host>/"   # expect 301 -> https
```

---

## Phase 3: Privilege Escalation (Pod Security)

```bash
# Containers running as root or allowing privilege escalation
kubectl get pods -A -o json | jq -r '.items[] | .metadata as $m | .spec.containers[],.spec.initContainers[]? |
  select(.securityContext.runAsUser==0 or .securityContext.runAsNonRoot==false or .securityContext.allowPrivilegeEscalation==true) |
  "\($m.namespace)/\($m.name): \(.name)"'

# Added capabilities / privileged
kubectl get pods -A -o json | jq -r '.items[] | .metadata as $m | .spec.containers[],.spec.initContainers[]? |
  select(.securityContext.privileged==true or (.securityContext.capabilities.add // [] | length > 0)) |
  "\($m.namespace)/\($m.name): \(.name) \(.securityContext.capabilities.add // [])"'
# Known intentional: media/qbittorrent gluetun init (NET_ADMIN) — CTR-001

# hostNetwork / hostPID / hostPath (expect none on app workloads)
kubectl get pods -A -o json | jq -r '.items[] |
  select(.spec.hostNetwork==true or .spec.hostPID==true or (.spec.volumes // [] | map(select(.hostPath)) | length > 0)) |
  "\(.metadata.namespace)/\(.metadata.name)"'

# Automounted SA tokens + what each SA can actually do
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>
```

---

## Phase 4: Secret / Data Exposure

```bash
# Every *.sops.yaml must be encrypted (look for a 'sops:' block; flag anything plaintext = CRED-001)
git ls-files '*.sops.yaml' | while read f; do grep -q '^sops:' "$f" || echo "UNENCRYPTED: $f"; done

# Secret manifests with literal data committed to git (should be none)
git grep -nE 'kind:\s*Secret' -- 'kubernetes/**/*.yaml' | head

# ClusterSecretStore scope (cluster-wide onepassword-connect = CRED-002)
kubectl get clustersecretstore -o wide
kubectl get externalsecret -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,STORE:.spec.secretStoreRef.name

# Secret values surfaced as plaintext env (CRED-003)
kubectl get pods -A -o json | jq -r '.items[] | .metadata as $m | .spec.containers[] |
  select((.env // []) | map(select(.value != null and (.name | test("PASS|TOKEN|SECRET|KEY"; "i")))) | length > 0) |
  "\($m.namespace)/\($m.name): \(.name)"'
```

---

## Phase 5: Supply Chain

```bash
# Unpinned :latest images (SC-001)
kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort -u | grep -E ':latest$|^[^:]+$'

# Flux sources + the secrets they reference (SC-002)
flux get sources all
kubectl get ocirepository,helmrepository,gitrepository -A -o wide

# Renovate automerge posture for critical components (read config)
git grep -n "automerge" -- .github/renovate.json5 .renovate/ 2>/dev/null
```

---

## Cleanup

```bash
kubectl delete pod sectest -n media --ignore-not-found
kubectl get pods -A | grep sectest   # confirm none remain
```
