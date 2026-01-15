# UniFi DNS (ExternalDNS)

Automatically manages DNS records in UniFi based on Kubernetes HTTPRoutes and Services.

## How It Works

1. **Watches** all `HTTPRoute` and `Service` resources in the cluster
2. **Filters** to only manage records matching `${SECRET_DOMAIN}`
3. **Creates** DNS records in UniFi pointing to the Gateway's LoadBalancer IP
4. **Tracks** ownership via TXT records (prefix: `k8s.main.`) to safely manage lifecycle

## What Gets Created

| HTTPRoute Gateway | UniFi DNS Points To |
|-------------------|---------------------|
| `envoy-internal`  | 192.168.20.51       |
| `envoy-external`  | 192.168.20.52       |

Both internal and external services get DNS records. This means LAN clients resolve directly to internal IPs, avoiding hairpin NAT through Cloudflare.

## Example

When you create:
```yaml
kind: HTTPRoute
metadata:
  name: myapp
spec:
  parentRefs:
    - name: envoy-internal
  hostnames:
    - myapp.hellhe.im
```

UniFi DNS automatically creates:
- `myapp.hellhe.im` → `192.168.20.51`
- `k8s.main.myapp.hellhe.im` (TXT record for ownership tracking)

When you delete the HTTPRoute, the DNS records are removed.

## Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| `policy` | `sync` | Creates AND removes records (vs `upsert-only`) |
| `txtOwnerId` | `main` | Identifies this cluster's records |
| `txtPrefix` | `k8s.main.` | Prefix for ownership TXT records |
| `domainFilters` | `${SECRET_DOMAIN}` | Only manages this domain |

## Authentication

Uses UniFi API key stored in 1Password (`unifi_api_token` → `credential` field).

## Troubleshooting

Check logs:
```bash
kubectl logs -n network -l app.kubernetes.io/name=unifi-dns
```

Verify DNS records in UniFi:
Network → Settings → DNS
