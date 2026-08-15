# mcpg-operator Helm chart

Installs the MCPG Kubernetes operator into a cluster.

## TL;DR

> **Beta note:** the chart is not yet published to a public registry —
> `https://charts.mcpg.dev` and `oci://ghcr.io/mcpg-dev/source-code/charts` are
> reserved but not live (tracked in
> [`docs/iac/DEFERRED.md`](https://mcpg.dev/docs/iac/)). Install from a local
> checkout for now. The admission webhook fails closed, so TLS must be real —
> enable cert-manager (recommended) or pre-provision the `tls.secretName` Secret.

```bash
helm install mcpg-operator ./helm/charts/mcpg-operator \
  --namespace mcpg-system \
  --create-namespace \
  --set certManager.enabled=true
```

## Prerequisites

- Kubernetes 1.28+.
- (Recommended) cert-manager 1.13+ for webhook TLS.
- (Recommended) prometheus-operator if using `serviceMonitor.enabled=true`.

## Configuration

See [`values.yaml`](./values.yaml) for the full default config.
The key surfaces:

| Group | Purpose |
|---|---|
| `image.*` | Operator container image. `image.repository` is the image NAME (`mcpg-operator`), joined onto `global.image.*` below; a value containing a `/` is used as an already-qualified repository. |
| `global.image.*` | `registry` (host, defaults to `ghcr.io`) + `repositoryPrefix` (`mcpg-dev/source-code`). Together they resolve the default `ghcr.io/mcpg-dev/source-code/mcpg-operator:<chart appVersion>`; repoint both for a mirrored install. |
| `serviceAccount.*` | Operator's ServiceAccount + IRSA / GKE WI annotations. |
| `webhook.*` | Validating webhook config (failurePolicy, bind address). |
| `certManager.*` | Auto-generated TLS via cert-manager. Recommended for production. |
| `tls.secretName` | Pre-provisioned TLS Secret (used when cert-manager disabled). |
| `operator.*` | Runtime config — log filter, watch namespace, resync interval. |
| `resources.*` | Operator pod resource caps (default: 100m / 128Mi → 1 / 512Mi). |
| `serviceMonitor.*` | prometheus-operator integration. |

## CRDs

The chart ships the 8 `mcpg.dev` CRDs under [`crds/`](./crds/). Per Helm's
rules, files in `crds/` are installed on the first `helm install` (any CRD that
already exists is left untouched), but Helm **never upgrades or deletes** them on
`helm upgrade` / `helm uninstall`. The `crd.install` and `crd.keepOnUninstall`
values are **advisory only** — they surface in NOTES and are consumed by the IaC
layer, but they do **not** gate the `crds/` directory, which Helm always
processes.

For an independent CRD lifecycle (GitOps / OLM / the Terraform `crds` module),
apply the CRDs out-of-band **before** the chart; Helm then skips the
pre-existing ones on install. To pick up CRD schema changes on upgrade, re-apply
the updated CRDs out-of-band (Helm will not):

```bash
kubectl apply -f helm/charts/mcpg-operator/crds/
```

CRDs are auto-generated from the Rust types via:

```bash
cargo run -p mcpg-operator --bin crdgen -- \
  --split-by-kind helm/charts/mcpg-operator/crds/
```

CI gates merges on the generated YAMLs being in-sync with the
checked-in versions.

## Upgrade

```bash
# Re-apply CRDs first (Helm does not upgrade crds/), then roll the release.
kubectl apply -f helm/charts/mcpg-operator/crds/
helm upgrade mcpg-operator ./helm/charts/mcpg-operator \
  --namespace mcpg-system \
  --reuse-values
```

There is **no** automatic CRD pre-upgrade hook — CRD schema changes must be
applied out-of-band (above) because Helm never upgrades its `crds/` dir. See
`docs/k8s-operator/rfcs/0010-upgrade-strategy.md`.

## Uninstall

```bash
# Soft uninstall — keeps CRDs + already-deployed gateways.
helm uninstall mcpg-operator --namespace mcpg-system

# Hard uninstall (after deleting every MCPGGateway in every namespace).
kubectl delete crd mcpggateways.mcpg.dev
```

## See also

- [`docs/k8s-operator/DEPLOYMENT.md`](https://mcpg.dev/docs/self-hosting/k8s-install)
- [`docs/k8s-operator/CRD_REFERENCE.md`](https://mcpg.dev/docs/reference/crds)
