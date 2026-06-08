---
name: sops-age
description: Use when encrypting, editing, or troubleshooting secrets in this repo. Covers SOPS with age keys, the project's .sops.yaml creation rules (talos/ full-encrypt vs kubernetes|bootstrap/ data-only), Flux kustomize-controller decryption via the sops-age secret, and the mise/Task workflow. Invoke for any *.sops.yaml file, "secret won't decrypt", external-secrets vs SOPS choices, or rotating the age key.
license: MIT
metadata:
  author: homelab-cluster
  version: "1.0.0"
  domain: infrastructure
---

# SOPS + age (this repo)

This cluster encrypts secrets with [SOPS](https://github.com/getsops/sops) using
**age** (not KMS or PGP). Flux's kustomize-controller decrypts them in-cluster at
reconcile time. Most app credentials come from **External Secrets + 1Password**;
SOPS is used for the small set of bootstrap/cluster secrets that must live in Git.

## When to use SOPS vs External Secrets

- **SOPS** — secrets that must exist before/independent of the cluster's secret
  plumbing: Talos machine secrets (`talos/talsecret.sops.yaml`), the bootstrap
  `sops-age` secret, `cluster-secrets`, and the `onepassword-connect` /
  `cert-manager` credentials needed to bootstrap External Secrets itself.
- **External Secrets (1Password)** — everything else. Prefer an `ExternalSecret`
  over a new `*.sops.yaml`. Only reach for SOPS when there's a chicken-and-egg
  dependency on the secret store.

## Environment (mise-managed)

`.mise.toml` sets these — they must be present in the shell:

- `SOPS_AGE_KEY_FILE = {{config_root}}/age.key` — the private age key (gitignored)
- `sops`, `age` provided via aqua; no global install needed

The public recipient is in `.sops.yaml`:
`age1qqfuvdaf3j7uczq5hjjg05074k4wyz0v4dg0luj4dza38vng95ns67feq9`.

## .sops.yaml creation rules

Two rules, matched top-down by path. **Always name files `*.sops.yaml`** so they
match and so Flux/kubeconform tooling skips them correctly.

| Path pattern | Encryption scope | Notes |
|-|-|-|
| `talos/*.sops.yaml` | whole file | Talos secrets have no `data`/`stringData` keys |
| `bootstrap\|kubernetes/*.sops.yaml` | only `data` and `stringData` | k8s Secret manifests; keys/structure stay readable |

Both rules set `mac_only_encrypted: true` — the MAC covers only encrypted values,
so you can edit plaintext fields (metadata, comments) without re-encrypting.

## Common operations

```bash
# Create a new k8s secret (lands under kubernetes/ → data/stringData encrypted)
sops kubernetes/apps/<ns>/<app>/app/secret.sops.yaml   # opens $EDITOR, encrypts on save

# Edit in place (decrypts to editor, re-encrypts on save)
sops kubernetes/apps/.../secret.sops.yaml

# Encrypt an existing plaintext manifest in place
sops --encrypt --in-place path/to/secret.sops.yaml

# View decrypted (do NOT redirect into a tracked file)
sops --decrypt path/to/secret.sops.yaml

# Re-encrypt to a NEW recipient after rotating keys (see Rotation below)
sops updatekeys path/to/secret.sops.yaml
```

A k8s Secret skeleton before encryption:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <name>
stringData:        # use stringData for plaintext values; SOPS encrypts the values
  KEY: value
```

## How Flux decrypts (the wiring)

1. `bootstrap/sops-age.sops.yaml` holds the age private key as a Secret named
   **`sops-age`** (key `age.agekey`) in `flux-system`. It's applied during
   bootstrap so the controller has the key.
2. `kubernetes/apps/flux-system/flux-instance/app/helmrelease.yaml` patches
   kustomize-controller with controller-level SOPS decryption pointing at that
   secret.
3. `kubernetes/flux/cluster/ks.yaml` sets `spec.decryption.provider: sops` on the
   Kustomizations, so every reconciled `*.sops.yaml` is decrypted automatically.

You do **not** add per-Kustomization decryption config for new secrets — inheriting
from the cluster Kustomization is enough. Just commit the `*.sops.yaml`.

## Validation before commit

- `sops --decrypt <file> >/dev/null` round-trips without error.
- The encrypted file still shows readable `apiVersion`/`kind`/`metadata` (proves
  `encrypted_regex` scoped to `data`/`stringData`).
- Never commit `age.key`, decrypted output, or `kubeconfig`.

## References

- `references/troubleshooting.md` — diagnosis runbook for decryption failures,
  creation-rule misses, MAC mismatches, and leaked plaintext.
- `references/key-rotation.md` — step-by-step age key rotation across the repo
  and the in-cluster `sops-age` secret.
