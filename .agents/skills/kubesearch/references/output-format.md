# KubeSearch Output Format

When presenting research findings, structure as:

```markdown
## <App/Chart> Configuration Research

### Common patterns
- Pattern 1: ...
- Pattern 2: ...

### Repository examples

#### <owner/repo> (X stars, chart vY.Z)
- Key configs: ...
- Notable: ...

#### <owner/repo>
...

### Suggested config for this repo
HelmRelease values adapted to our OCIRepository + app-template conventions
(versions tracked in versions.env, secrets via SOPS/external-secrets):

```yaml
# kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml — spec.values excerpt
...
```
```
