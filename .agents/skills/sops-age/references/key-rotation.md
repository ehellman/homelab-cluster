# age key rotation

Rotate the cluster's age key pair and re-encrypt every SOPS file to the new
recipient. Do this if `age.key` may have leaked, or on a periodic schedule.

The single recipient lives in `.sops.yaml` and the matching private key exists in
two places: your local `age.key` (gitignored) and the in-cluster `sops-age` secret
(`bootstrap/sops-age.sops.yaml`, applied to `flux-system`).

## Steps

1. **Generate the new key pair.**
   ```bash
   age-keygen -o age.key.new
   # note the "Public key:" line it prints — that's the new recipient
   ```

2. **Add the new recipient to `.sops.yaml`** (both creation rules). You can keep
   the old recipient temporarily so files remain decryptable during the rollover,
   or replace it outright if you re-encrypt everything in the same change.

3. **Re-encrypt every SOPS file to the current recipient set.**
   ```bash
   # SOPS_AGE_KEY_FILE must still point at a key that can decrypt (the old one)
   find . -type f -name '*.sops.yaml' -exec sops updatekeys -y {} \;
   ```
   `updatekeys` rewrites each file's key metadata to match `.sops.yaml` without
   changing the plaintext.

4. **Update the in-cluster private key.** Re-create `bootstrap/sops-age.sops.yaml`
   so its `age.agekey` is the *new* private key, encrypted to the new recipient:
   ```bash
   cat age.key.new | sops --encrypt --input-type binary --output-type binary \
     /dev/stdin > /tmp/agekey.enc   # or edit bootstrap/sops-age.sops.yaml via `sops`
   ```
   Then apply it so kustomize-controller picks up the new key:
   ```bash
   sops --decrypt bootstrap/sops-age.sops.yaml | kubectl apply -f -
   ```

5. **Swap your local key** and drop the old recipient from `.sops.yaml` once
   everything is re-encrypted:
   ```bash
   mv age.key.new age.key
   find . -name '*.sops.yaml' -exec sops updatekeys -y {} \;   # now only new recipient
   ```

6. **Commit and reconcile.**
   ```bash
   flux reconcile kustomization flux-system --with-source
   flux get kustomizations -A   # all should be Ready
   ```
   Spot-check a consumer (e.g. a HelmRelease that reads a SOPS value) still
   resolves.

## Notes

- Keep the old key available until step 5 completes — losing decrypt capability
  mid-rotation strands every file.
- Talos secrets (`talos/*.sops.yaml`) use the same recipient and are covered by
  the `find ... updatekeys` sweep.
- Back up the new `age.key` to your password manager immediately.
