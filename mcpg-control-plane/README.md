# mcpg-control-plane

Helm chart that deploys the [MCPG Control Plane](https://mcpg.dev/docs/cloud/)
(binary `mcpg-cp`, image `mcpg-control-plane-server`) into Kubernetes — operator UI, gRPC agent
contract for gateways, audit ledger, mTLS PKI, OIDC PKCE login.

This chart pairs with:
- [`mcpg-operator`](../mcpg-operator/) — manages
  `MCPGGateway` / `MCPGPlugin` / `MCPGPluginSet` CRDs.
- [`mcpg`](../mcpg/) — the gateway itself; gateways register
  with this CP via the gRPC contract on port 7844.

## TL;DR

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency build helm/charts/mcpg-control-plane
helm install cp ./helm/charts/mcpg-control-plane

kubectl port-forward svc/cp-mcpg-control-plane 7843:7843
open http://localhost:7843
```

For the full stack (operator + CP), install the operator chart in
the same release namespace:

```bash
helm install mcpg-operator ./helm/charts/mcpg-operator
helm install cp           ./helm/charts/mcpg-control-plane
```

(A meta-chart that bundles both is on hold until Helm fixes a
3.20-era regression with `file://` sub-chart references — see
helm/helm#14062 — or until the charts are published to an OCI
registry.)

That single command spins up a Tier-0 wedge install — single replica,
SQLite on the pod's ephemeral filesystem, no auth (loopback only).
Production knobs are below.

## Production checklist

- [ ] **Persistence** — `--set persistence.enabled=true` for SQLite,
      OR `--set postgresql.enabled=true` to run on Bitnami's
      Postgres sub-chart, OR `--set externalDatabase.enabled=true`
      for an existing managed Postgres.
- [ ] **Auth** — `--set auth.mode=oidc` plus
      `auth.oidc.{issuer,clientId,clientSecret}`. Otherwise anyone
      reachable on the HTTP port can mint enrollment tokens.
- [ ] **Ingress** — `--set ingress.enabled=true` with TLS at the
      ingress; the cp-server itself runs HTTP-only, by design.
- [ ] **gRPC TLS** — `--set cp.grpcTls=true` so gateway agents
      negotiate TLS on port 7844. The CP mints its own CA at
      first boot; agents fetch it via `/v1/ca-cert.pem`.
- [ ] **License** (paid self-host only) — `license.secretRef` +
      `license.pubkeyPem`/`license.pubkeySecretRef`. Skip for
      OSS/community installs.

## Offline license (self-host enterprise)

A paid self-host install activates by mounting the license JWT issued
offline with `mcpg-license issue` (no cloud round-trip):

```bash
kubectl create secret generic mcpg-license \
  --from-file=license.jwt=acme.lic \
  --from-file=pubkey.pem=lic.pub.pem

helm upgrade cp ./helm/charts/mcpg-control-plane \
  --set license.secretRef=mcpg-license \
  --set license.pubkeySecretRef=mcpg-license
```

The chart mounts the Secret read-only and sets `MCPG_CP_LICENSE_FILE` +
`MCPG_CP_LICENSE_PUBKEY_PEM`. The CP verifies the token against the key
at **every boot** and installs it for the org named by the license's
`tenant_slug` (creating the org when absent; issue with
`--tenant-slug default` to license the bootstrap org of a single-tenant
install). Verification is fail-closed: a malformed, expired, tampered,
or key-mismatched license **refuses boot** instead of silently running
community. Rotation/renewal is restart-driven — update the Secret and
restart the Deployment (`kubectl rollout restart deploy/<name>`).

## Database modes

| `cp.dbUrl` | `postgresql.enabled` | `externalDatabase.enabled` | Resulting URL                                                        |
|---|---|---|---|
| set        | —     | —     | the explicit value                                                   |
| empty      | true  | —     | `postgresql://<user>:$(MCPG_CP_DB_PASSWORD)@<release>-postgresql:5432/<db>` |
| empty      | false | true  | same shape when `existingSecret` is set; password-less otherwise     |
| empty      | false | false | `sqlite:///var/lib/mcpg-cp/state.db?mode=rwc`                        |

The Postgres password is delivered as the `MCPG_CP_DB_PASSWORD` env var
(sourced from the relevant Kubernetes Secret, declared before the DSN) and
spliced into `MCPG_CP_DB_URL` by Kubernetes dependent-env expansion — the
binary only ever reads the complete DSN. Passwords containing `$(`, `)` or
characters needing URL-encoding should be delivered via a full `cp.dbUrl`
instead.

## Values reference

See [`values.yaml`](./values.yaml) for the full set; the most
common knobs are:

| Path                    | Default                             | Purpose                                                       |
|---|---|---|
| `replicaCount`          | `1`                                 | Replicas. `> 1` requires a shared Postgres (render-guarded); see [Multi-replica (HA)](#multi-replica-ha). |
| `cp.assumeExternalDbUrl`| `false`                             | Declare an envFrom-delivered Postgres DSN so `replicaCount > 1` passes the sqlite render guard. |
| `podDisruptionBudget.*` | `enabled: true`, `minAvailable: 1`  | PDB, emitted only when `replicaCount > 1`.                    |
| `serviceMonitor.enabled`| `false`                             | Scrape `/metrics` on the http port (prometheus-operator CRDs required). |
| `prometheusRule.enabled`| `false`                             | Default CP alert pack (target down/absent, 5xx ratio, license-refresh failures). |
| `grafanaDashboard.enabled` | `false`                          | Grafana dashboard ConfigMap (`grafana_dashboard: "1"` sidecar label). |
| `image.tag`             | chart `appVersion`                  | Pin to a specific cp-server build.                            |
| `image.repository`      | `mcpg-control-plane-server`         | Image NAME, joined onto `global.image.repositoryPrefix`. A value containing a `/` is used as an already-qualified repository. |
| `global.image.*`        | `registry` (host, defaults `ghcr.io`) + `repositoryPrefix` (`mcpg-dev/source-code`) | Resolve to `ghcr.io/mcpg-dev/source-code/mcpg-control-plane-server:<appVersion>`. Repoint both for a mirrored install; Helm merges `global` down from an umbrella chart. |
| `cp.externalUrl`        | `http://localhost:7843`             | Used in enrollment URLs and OIDC redirect URI.                |
| `cp.grpcTls`            | `false`                             | Turn on gRPC TLS (agent ↔ CP).                                |
| `cp.grpcMtls`           | `false`                             | Require client certs on gRPC. Implies `grpcTls`.              |
| `auth.mode`             | `none`                              | `none` / `oidc` / `mock`.                                     |
| `auth.oidc.*`           | unset                               | OIDC issuer, client id, client secret (Secret-injected).      |
| `license.secretRef`     | unset                               | Existing Secret with the offline license JWT (self-host enterprise). |
| `license.pubkeyPem` / `license.pubkeySecretRef` | unset       | License verification key (Ed25519 SPKI PEM), inline or Secret-sourced. |
| `persistence.enabled`   | `false`                             | PVC for SQLite when no Postgres is configured.                |
| `ingress.enabled`       | `false`                             | Standard Ingress for the HTTP UI.                             |
| `postgresql.enabled`    | `false`                             | Bundle Bitnami Postgres sub-chart.                            |
| `externalDatabase.*`    | unset                               | Point at your own Postgres instead.                           |
| `cp.kubeProvider.enabled` | `false`                           | Watch MCPGGateway CRDs as the inventory source. Image must be built with `--features kube-provider`. |
| `cp.kubeProvider.namespace` | `""`                            | Empty ⇒ cluster-wide; set to a single namespace for per-tenant CPs. |

## Multi-replica (HA)

Multi-replica is a **Postgres-only** configuration. The replica-shared
secrets live in the database — the cookie signing key and the CP CA in
the `cluster_secrets` table, tenant payload DEKs in
`tenant_payload_keys` (all envelope-encrypted at rest) — and the
periodic janitors coordinate through `leader_leases`, so N replicas on
one shared Postgres serve interchangeable sessions and agent mTLS.
SQLite is pod-local and single-writer: the chart **fails to render**
`replicaCount > 1` unless one of `cp.dbUrl` (postgres://…),
`postgresql.enabled`, or `externalDatabase.enabled` is set.

```bash
helm upgrade cp ./helm/charts/mcpg-control-plane \
  --set replicaCount=3 \
  --set externalDatabase.enabled=true \
  --set externalDatabase.host=pg.internal \
  --set externalDatabase.existingSecret=cp-db
```

On the Postgres path the Deployment rolls with `RollingUpdate`
(`maxUnavailable: 0`, `maxSurge: 1`) and a PodDisruptionBudget
(`minAvailable: 1`) is emitted, so upgrades and node drains keep at
least one replica serving. The sqlite path keeps `Recreate` — two
writers must never share the state PVC.

When the Postgres DSN is delivered out-of-band via
`extraEnv`/`extraEnvFrom` (the managed pattern that keeps credentials
out of rendered manifests), the chart cannot detect it at render time —
set `cp.assumeExternalDbUrl=true` to pass the guard:

```bash
helm upgrade cp ./helm/charts/mcpg-control-plane \
  --set replicaCount=2 \
  --set cp.assumeExternalDbUrl=true \
  --set 'extraEnvFrom[0].secretRef.name=cp-db-env'   # provides MCPG_CP_DB_URL
```

Load-balance both `:7843` (HTTP) and `:7844` (gRPC); agents pin their
channel to whichever replica their TCP connection landed on, and
cross-replica config pushes route through the database.

## Observability pack

Three flag-gated, off-by-default resources (they need the
prometheus-operator CRDs / a Grafana sidecar, and a cp-server build
that serves the global `/metrics` endpoint):

- `serviceMonitor.enabled=true` — scrapes `/metrics` on the http port
  (plain HTTP; TLS terminates at the ingress).
- `prometheusRule.enabled=true` — alert pack: target down / target
  absent, HTTP 5xx ratio (`prometheusRule.thresholds.http5xxRatio`,
  default 5%), and license-refresh failures.
- `grafanaDashboard.enabled=true` — dashboard ConfigMap (label
  `grafana_dashboard: "1"`): requests by route class, 5xx ratio,
  license-refresh outcomes, enrollments, publishes.

## Federation

Federation login (`mcpg cloud login`, license JWTs from
`auth.mcpg.dev`) lives outside this chart — see
<https://mcpg.dev/docs/cloud/licensing>.
