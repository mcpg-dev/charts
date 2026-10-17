# MCPG Helm charts

Helm charts for deploying [MCPG](https://mcpg.dev), published as OCI
packages:

```sh
helm install mcpg oci://ghcr.io/mcpg-dev/charts/mcpg --version <chart-version>
```

Always pass `--version`. The charts are prereleases (`0.1.0-beta.N`), and
without it Helm installs the highest stable-numbered chart in the registry,
which is an older chart, not the current one. Each chart's package page
(`https://github.com/orgs/mcpg-dev/packages/container/package/charts%2F<chart>`)
lists its versions.

| Chart | Deploys | Licence |
|---|---|---|
| `mcpg` | the MCPG gateway | Apache-2.0 |
| `mcpg-operator` | the Kubernetes operator (CRDs + controller) | BUSL-1.1 |

Each chart's own README documents its values. Charts version
independently, so releases are per chart in the OCI registry rather than
tags on this repository.

## Licence

This repository is Apache-2.0 (`LICENSE`), except a chart directory that
carries its own `LICENSE`: `mcpg-operator` is Business Source License 1.1,
free for production use in your own organization. See
<https://mcpg.dev/license>.

Development happens upstream — file issues here (see `CONTRIBUTING.md`).
