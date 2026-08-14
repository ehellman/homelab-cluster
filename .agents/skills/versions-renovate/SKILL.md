---
name: versions-renovate
description: |
  Managing dependency versions and Renovate annotations in the homelab.

  Use when: (1) Pinning a new chart/image version, (2) Configuring Renovate to track a new dependency,
  (3) Debugging why Renovate ignores or mis-detects a version, (4) Understanding `# renovate:` annotation syntax,
  (5) Adding container image tracking to YAML files, (6) Configuring package rules or grouping in Renovate.

  Triggers: "renovate annotation", "renovate not updating", "add version", "pin version",
  "renovate ignore", "datasource", "package rule", "automerge",
  "renovate config", "dependency tracking", "version management", "talenv"
user-invocable: false
---

# Versions and Renovate Management

**There is no `versions.env` and no `kubernetes/platform/` directory in this repo.**
Versions are pinned **inline**, at the point of use:

| What | Where |
|-|-|
| Helm chart version | `HelmRelease` → `spec.chart.spec.version` |
| OCI chart / image tag | `OCIRepository` → `spec.ref.tag` |
| Container image tag | app-template values → `containers.<name>.image.tag` |
| Talos + Kubernetes | `clusters/homelab/talos/talenv.yaml` (annotated) |
| Bootstrap CRD charts | `clusters/homelab/bootstrap/helmfile.d/*.yaml` |

Renovate config is **`.renovaterc.json5` at the repo root** (not `.github/renovate.json5`).

Flux `postBuild.substituteFrom` pulls from the `cluster-secrets` Secret and is for values
like `${SECRET_DOMAIN}` — it is **not** used for versions.

## How Renovate finds things

Most updates need **no annotation** — native managers handle them:

- `flux` / `kubernetes` managers: any `.yaml` under a `kubernetes/` path
- `helmfile` manager: `helmfile.d/*.yaml`
- a custom manager auto-detects bare `oci://<image>:<tag>` in any YAML

Annotations are only needed where a version sits in a plain key the native managers
can't interpret — e.g. `talenv.yaml`.

## Annotation Syntax

The custom regex manager supports **three** fields only:

```yaml
# renovate: datasource=<source> depName=<name> [repository=<url>]
key: <value>
```

```yaml
# renovate: datasource=docker depName=ghcr.io/siderolabs/installer
talosVersion: v1.13.3
```

- The annotation must sit **immediately above** the `key: value` (or `KEY=value`) line.
- `repository=` is the Helm repo URL — note it is **`repository=`, not `registryUrl=`**.
- `datasource` may be omitted; it defaults to `github-releases`.
- `packageName`, `extractVersion` and `versioning` are **not** wired into this repo's
  custom manager. If you need them, add a `packageRules` entry keyed on `matchDepNames`
  instead of inventing annotation fields.

Datasource picking:

```
HTTP Helm registry  --> datasource=helm  + repository=<url>
OCI Helm / image    --> datasource=docker  (depName = full path, no oci:// prefix)
GitHub release      --> datasource=github-releases  (depName = org/repo)
```

## YAML Container Image Annotations

For image tags in Helm values that a native manager misses:

```yaml
image:
  repository: ghcr.io/kashalls/kromgo
  # renovate: datasource=docker depName=ghcr.io/kashalls/kromgo
  tag: v0.7.5
```

## Package Rules

Add to `.renovaterc.json5` under `packageRules` to group or gate updates:

```json5
{
  matchDepNames: ["my-chart", "related-chart"],
  groupName: "my stack",
}
```

`matchDepNames` must match the `depName` Renovate reports (see the Dependency Dashboard issue).
The flux-operator group is the worked example — it uses `minimumGroupSize: 3` so the operator,
instance and manifests always move together.

**Automerge is deliberately narrow.** Only two rules enable it:

- `github-actions` — minor/patch/digest, after `minimumReleaseAge: "3 days"`
- `mise` — minor/patch

Everything else (charts, container images, Talos, Terraform) opens a PR for manual review.
There is no `.renovate/` directory and no `task renovate:validate`.

Renovate runs on `schedule: ["every weekend"]` and ignores `**/*.sops.*`.

## Debugging

| Symptom | Cause | Fix |
|-|-|-|
| Silently ignored | Annotation not directly above the value line | Move it immediately above |
| Silently ignored | Used `registryUrl=` | This repo's regex expects `repository=` |
| Nothing detected in a new file | Path not matched by a manager | Custom manager covers `*.env`, `*.sh`, `*.yaml` |
| Can't find OCI chart | `datasource=helm` used for OCI | Use `datasource=docker`, drop `oci://` |
| Wrong package looked up | `oci://` prefix left in `depName` | Remove the prefix |
| Two PRs for one component | Chart and CRD tracked separately | Group them via `packageRules` |

Also check the Dependency Dashboard issue (`Renovate Dashboard :robot:`) and `ignorePaths`.
