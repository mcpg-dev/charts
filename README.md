# MCPG Helm charts

Helm charts for deploying [MCPG](https://mcpg.dev), published as OCI
packages:

```sh
helm install mcpg oci://ghcr.io/mcpg-dev/charts/mcpg
```

| Chart | Deploys |
|---|---|
| `mcpg` | the MCPG gateway |
| `mcpg-operator` | the Kubernetes operator (CRDs + controller) |
| `mcpg-control-plane` | the self-hosted control plane |
| `mcpg-keycloak` | a bundled Keycloak for identity |

Each chart's own README documents its values. Charts version
independently, so releases are per chart in the OCI registry rather than
tags on this repository.

Development happens upstream — file issues here (see `CONTRIBUTING.md`).
