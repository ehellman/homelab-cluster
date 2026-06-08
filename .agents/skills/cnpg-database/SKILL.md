---
name: cnpg-database
description: |
  CloudNative-PG (CNPG) PostgreSQL management for this homelab. Covers the shared
  cluster vs dedicated per-app clusters, provisioning credentials via ExternalSecret
  + 1Password, wiring apps to consume the DB, PodMonitor, and debugging cluster health.

  Use when: (1) Adding a database for a new app, (2) Deciding shared vs dedicated cluster,
  (3) Creating a CNPG Cluster manifest under clusters/, (4) Setting up DB credentials,
  (5) Wiring an app to a Postgres connection, (6) Debugging CNPG pods, PVCs, or health.

  Triggers: "database", "postgresql", "postgres", "cnpg", "cloudnative-pg",
  "postgres-shared", "postgres cluster", "db credentials", "db password",
  "ExternalSecret postgres", "cnpg status", "database namespace", "vectorchord"
user-invocable: false
---

# CNPG Database Management

All Postgres runs in the `database` namespace via the CloudNative-PG operator. Two Flux
Kustomizations (`kubernetes/apps/database/cloudnative-pg/ks.yaml`):

| Kustomization | Path | Contains |
|-|-|-|
| `cloudnative-pg` | `./app` | Operator HelmRelease + CRDs |
| `cloudnative-pg-clusters` | `./clusters` | Cluster CRs + credential ExternalSecrets |

`cloudnative-pg-clusters` `dependsOn` the operator plus `external-secrets` and
`onepassword-connect`. Everything is a single file per concern in `clusters/`, registered in
`clusters/kustomization.yaml`.

## When to use this skill

| Task | Action |
|-|-|
| App needs a standard relational DB | Reuse `postgres-shared` (add a DB + credentials) |
| App needs extensions (e.g. pgvector/vchord) or isolation | Dedicated Cluster |
| App needs a specific PG major version | Dedicated Cluster |
| Just reading/debugging cluster state | Jump to [Debugging](#debugging) |

## Decision: shared vs dedicated cluster

```
Standard workload, default Postgres image       -> reuse postgres-shared
Needs extensions (vectorchord, postgis, etc.)   -> dedicated Cluster, custom imageName
Needs a pinned/different PG major version        -> dedicated Cluster
Strong data/perf isolation wanted                -> dedicated Cluster
```

Existing clusters for reference:

| Cluster | Instances | Image | Storage | Owner DB |
|-|-|-|-|-|
| `postgres-shared` | 3 | `ghcr.io/cloudnative-pg/postgresql:18` | 20Gi | none (shared) |
| `postgres-immich` | 2 | `ghcr.io/tensorchord/cloudnative-vectorchord:16-0.5.3` | 10Gi | `immich` |
| `postgres-n8n` | 1 | `ghcr.io/cloudnative-pg/postgresql:16.6-bookworm` | 5Gi | `n8n` |

Storage class is always `ceph-block`. Every Cluster sets `monitoring.enablePodMonitor: true`.

## Workflow: dedicated cluster for a new app

Files go in `kubernetes/apps/database/cloudnative-pg/clusters/`. Use `<app>` for the app name.

### Step 1 — Credentials ExternalSecret (`<app>-secrets.yaml`)

One ExternalSecret for the superuser, one for the app user. Both pull from the
`postgres_<app>` item in 1Password via the `onepassword-connect` ClusterSecretStore.

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: postgres-<app>-superuser
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: postgres-<app>-superuser
    template:
      engineVersion: v2
      data:
        username: "{{ .username }}"
        password: "{{ .password }}"
  data:
    - secretKey: username
      remoteRef: { key: postgres_<app>, property: superuser_username }
    - secretKey: password
      remoteRef: { key: postgres_<app>, property: superuser_password }
```

Add a second, identical ExternalSecret named `postgres-<app>-user` whose `remoteRef`
properties are `username` and `password` (no `superuser_` prefix) — see
`clusters/immich-secrets.yaml` / `clusters/n8n-secrets.yaml`.

Secret naming is fixed: `postgres-<app>-superuser` and `postgres-<app>-user`, keys
`username`/`password`. The 1Password item `postgres_<app>` must hold `superuser_username`,
`superuser_password`, `username`, `password`. Create that item before reconciling.

### Step 2 — Cluster manifest (`<app>.yaml`)

`initdb.secret` points at the app-user secret, so CNPG creates the role/owner from it.
`superuserSecret` points at the superuser secret.

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-<app>
spec:
  instances: 2
  imageName: ghcr.io/cloudnative-pg/postgresql:18   # or an extension image
  primaryUpdateStrategy: unsupervised

  enableSuperuserAccess: true
  superuserSecret:
    name: postgres-<app>-superuser

  postgresql:
    parameters:
      timezone: "Europe/Stockholm"
      log_timezone: "Europe/Stockholm"
    # shared_preload_libraries: [vchord.so]   # only if using extensions

  bootstrap:
    initdb:
      database: <app>
      owner: <app>
      secret:
        name: postgres-<app>-user
      # postInitApplicationSQL:                # extensions go here
      #   - CREATE EXTENSION IF NOT EXISTS vchord CASCADE;

  storage:
    size: 10Gi
    storageClass: ceph-block

  resources:
    requests: { memory: 512Mi, cpu: 100m }
    limits: { memory: 2Gi }

  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname

  monitoring:
    enablePodMonitor: true
```

For an extensions example see `clusters/immich.yaml` (vectorchord + `postInitApplicationSQL`).

### Step 3 — Register both files

Add to `clusters/kustomization.yaml` `resources`, secrets file before the cluster file:

```yaml
  - ./<app>-secrets.yaml
  - ./<app>.yaml
```

### Step 4 — Wire the app

CNPG exposes services in the `database` namespace: `postgres-<app>-rw` (primary),
`-ro` (replicas), `-r` (any). The app reads its own credentials, not the cluster's secret
directly. In this repo the app's own ExternalSecret pulls the same `postgres_<app>`
1Password item and builds a connection string (see `kubernetes/apps/media/immich/app/external-secret.yaml`):

```
DB_HOSTNAME: postgres-<app>-rw.database.svc.cluster.local
DB_URL: postgresql://{{ .db_username }}:{{ .db_password }}@postgres-<app>-rw.database.svc.cluster.local:5432/<app>
```

Port is always `5432`. There is no PgBouncer/pooler — apps connect to `-rw` directly.

## Reusing postgres-shared

`postgres-shared` has no app-owned DB by default. To host an app there, add a CNPG
`Database` CR (`postgresql.cnpg.io/v1`, `kind: Database`) targeting `cluster.name:
postgres-shared` and an ExternalSecret for the role, then point the app at
`postgres-shared-rw.database.svc.cluster.local`. Prefer a dedicated cluster when the app
needs extensions or a different PG version.

## Monitoring

Each Cluster sets `monitoring.enablePodMonitor: true`. kube-prometheus-stack discovers the
PodMonitor cluster-wide; the operator HelmRelease also enables `monitoring.podMonitorEnabled`
and creates a Grafana dashboard. No manual ServiceMonitor needed.

## Validation

```bash
task template:validate-kubernetes-config   # kubeconform on rendered manifests
task reconcile                              # force Flux to pull + apply
```

Checklist before committing:

- [ ] `postgres-<app>-secrets.yaml` and `postgres-<app>.yaml` exist in `clusters/`
- [ ] Both registered in `clusters/kustomization.yaml` (secrets first)
- [ ] 1Password item `postgres_<app>` has all four properties
- [ ] Secret names match `postgres-<app>-{superuser,user}`
- [ ] `storageClass: ceph-block`, `monitoring.enablePodMonitor: true`
- [ ] App points at `postgres-<app>-rw.database.svc.cluster.local:5432`
- [ ] `task template:validate-kubernetes-config` passes

## Debugging

```bash
kubectl get cluster -n database                      # phase / instances / primary
kubectl describe cluster postgres-<app> -n database  # events, conditions
kubectl cnpg status postgres-<app> -n database       # cnpg plugin: replication, WAL
kubectl get pods -n database -l cnpg.io/cluster=postgres-<app>
kubectl get pvc -n database                          # ceph-block volumes
kubectl get externalsecret -n database               # SecretSynced status
kubectl logs -n database postgres-<app>-1            # instance logs
```

| Symptom | Cause | Fix |
|-|-|-|
| Pods Pending | No PVC bound | Check `ceph-block` StorageClass / Ceph health |
| ExternalSecret `SecretSyncedError` | 1Password item/property missing | Verify `postgres_<app>` item + property names |
| Cluster stuck initializing | `initdb.secret` missing/empty | Ensure `postgres-<app>-user` synced first |
| App auth failed | Wrong DB user secret | App must use `username`/`password`, host `-rw` |
| CrashLoopBackOff | OOM or bad PG param | Check logs, raise `resources.limits.memory` |
| Extension missing | Wrong image | Use an image bundling it + `postInitApplicationSQL` |

There is currently no barman/object-store backup configured.
