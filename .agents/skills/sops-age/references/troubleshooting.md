# SOPS + age troubleshooting

Diagnosis runbook for the most common failure modes in this repo. Work top-down;
each symptom lists how to confirm it and how to fix it.

## "Secret won't decrypt" — Flux Kustomization/HelmRelease stuck

The kustomize-controller can't decrypt a `*.sops.yaml` it's reconciling.

```bash
# See the actual error on the failing Kustomization
flux get kustomizations -A
kubectl -n flux-system describe kustomization <name> | rg -i "sops|decrypt|error"

# Confirm the decryption key secret exists and is the right shape
kubectl -n flux-system get secret sops-age -o jsonpath='{.data.age\.agekey}' | base64 -d | head -1
# -> should print: AGE-SECRET-KEY-...  (a private key, not the public recipient)
```

Causes and fixes:

- **Recipient mismatch** — the file was encrypted to a different age recipient
  than the private key in `sops-age`. Happens after a key rotation where files
  weren't re-encrypted. Fix: `sops updatekeys <file>` (see `key-rotation.md`).
- **`sops-age` secret missing** — bootstrap step didn't run. Re-apply
  `bootstrap/sops-age.sops.yaml` (decrypted) into `flux-system`.
- **Kustomization missing `decryption.provider: sops`** — only relevant for a new
  top-level Kustomization. Children of `kubernetes/flux/cluster/ks.yaml` inherit
  it; don't re-add per app.

## `sops: no matching creation rules`

The path doesn't match any `path_regex` in `.sops.yaml`.

- Filename must end in `.sops.yaml` (or `.sops.yml`).
- Path must be under `talos/`, `bootstrap/`, or `kubernetes/`.
- Check with: `grep -A2 path_regex .sops.yaml`.

## `Failed to get the data key` (local `sops` command)

Your shell can't find the private key.

```bash
echo $SOPS_AGE_KEY_FILE        # must point at <repo>/age.key
test -f age.key && echo present || echo MISSING
mise doctor                    # confirm mise env is active in this dir
```

Fix: `cd` into the repo so mise loads `.mise.toml`, or `mise trust`. If `age.key`
is genuinely gone, restore it from your password manager / backup — it cannot be
regenerated and without it nothing decrypts.

## MAC mismatch / "Hash of decrypted data does not match"

An encrypted value was edited outside SOPS, or the file was hand-merged.

- Always edit via `sops <file>` — never a plain text editor on encrypted values.
- For a bad git merge of a `*.sops.yaml`, take one side whole (`git checkout
  --theirs/--ours <file>`) then re-edit with `sops`, rather than merging hunks.
- `mac_only_encrypted: true` means editing *plaintext* fields (metadata, comments)
  by hand is fine — only encrypted values trip the MAC.

## Plaintext secret leaked into Git

If a real value was committed unencrypted (even once):

1. Treat it as compromised. Rotate the value at its source (1Password / provider),
   not just in the repo — git history retains the old value.
2. Replace the file with a properly encrypted `*.sops.yaml`.
3. History scrubbing (filter-repo/BFG) is optional and only meaningful if the
   value can't be rotated; rotation is the real fix.

## Verifying an encrypted file is well-formed

```bash
sops --decrypt path/to/secret.sops.yaml >/dev/null && echo "decrypt OK"
# apiVersion/kind/metadata should remain readable in the encrypted file:
rg -n "apiVersion|kind:|name:" path/to/secret.sops.yaml
```
