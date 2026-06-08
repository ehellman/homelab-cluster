---
name: kubesearch
description: |
  Research how other homelabbers configure apps and HelmReleases by searching kubesearch.dev,
  then fetching their real configs from GitHub. Near-zero coupling to this repo — pure research workflow.

  Use when: (1) Configuring a new app/HelmRelease and want real-world examples,
  (2) Looking for example values for a bjw-s app-template app or a native chart,
  (3) Comparing how repos wire ingress/storage/sidecars/env for a given app,
  (4) Finding patterns for a specific chart or container image, (5) Sanity-checking an unusual option.

  Triggers: "kubesearch", "how do others configure", "show me examples", "helm chart examples",
  "values.yaml examples", "app-template examples", "real-world config", "compare helm configs",
  "how do other homelabs", "example HelmRelease for", "what values do people use for"
user-invocable: false
---

# KubeSearch — Homelab Config Research

Search [kubesearch.dev](https://kubesearch.dev) to find how other Flux/GitOps homelabs configure
an app, then pull their actual manifests from GitHub. Works for both **bjw-s app-template**
(`oci://ghcr.io/bjw-s-labs/helm/app-template`) apps and **native charts** — kubesearch indexes
HelmReleases regardless of chart source, so you can find example `values:` for either.

## Workflow

**Step 1 — Find the chart/app:** `WebFetch https://kubesearch.dev/?search=<name>` → lists matching
releases with their registry paths and a repo count per release.

**Step 2 — Get repo links:** Convert the registry path to a URL slug (replace `/` with `-`), then
`WebFetch https://kubesearch.dev/hr/<slug>` → lists repositories with direct GitHub links to each
HelmRelease file.

| Registry path | Slug for `/hr/<slug>` |
|-|-|
| `ghcr.io/bjw-s-labs/helm/app-template` | `ghcr.io-bjw-s-labs-helm-app-template` |
| `ghcr.io/grafana/helm-charts/grafana` | `ghcr.io-grafana-helm-charts-grafana` |
| `charts.longhorn.io/longhorn` | `charts.longhorn.io-longhorn` |

**Step 3 — Fetch configs:** Convert each GitHub blob URL to its raw form and `WebFetch` 3–5 in parallel:
- Blob: `github.com/<owner>/<repo>/blob/<branch>/<path>`
- Raw:  `raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`

**Selection criteria:** recent activity (commits within ~6 months), more stars, similar chart version,
and similar stack (Talos, Flux, bare-metal, OCIRepository-based). Prefer repos that resemble this one.

## Mapping findings back to this repo

This repo's apps live at `kubernetes/apps/<namespace>/<app>/` with a Flux `HelmRelease` whose
`spec.chartRef` points at an `OCIRepository` or `HelmRepository`. When adapting an example:

- Keep this repo's `chartRef` + `OCIRepository` pattern; copy only the `spec.values:` ideas.
- For app-template apps, map their `controllers`/`service`/`ingress`/`persistence` blocks onto ours.
- Chart/image versions belong in `kubernetes/platform/versions.env` (see `versions-renovate` skill),
  not pinned inline — take the *shape* of the config from kubesearch, not the version numbers.
- Secrets go through SOPS or external-secrets here — never copy plaintext creds from an example.

## Common repos worth checking

| Repository | Focus |
|-|-|
| `onedr0p/home-ops` (home-operations) | Flux + Talos, app-template heavy |
| `bjw-s-labs/home-ops` | Canonical app-template patterns |
| `buroa/k8s-gitops` | Talos + Flux |
| `mirceanton/home-ops` | Well-documented configs |

See [references/output-format.md](references/output-format.md) for how to present findings.
