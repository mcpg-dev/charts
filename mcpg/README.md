# MCPG Helm Chart

Production-grade Helm chart for deploying the [Model Context Protocol Gateway](https://mcpg.dev/docs/gateway/) on Kubernetes.

## Prerequisites

- Kubernetes 1.26+
- Helm 3.x
- Container image built from `apps/gateway/Dockerfile`

## Install

```bash
# Add dependencies (first time only)
cd helm/charts/mcpg && helm dependency build

# Single-instance (quick start)
helm install mcpg ./helm/charts/mcpg

# Multi-instance with bundled NATS
helm install mcpg ./helm/charts/mcpg \
  --set replicaCount=3 \
  --set nats.enabled=true

# Multi-instance with bundled Redis
helm install mcpg ./helm/charts/mcpg \
  --set replicaCount=3 \
  --set redis.enabled=true

# From a values file
helm install mcpg ./helm/charts/mcpg -f my-values.yaml
```

## Uninstall

```bash
helm uninstall mcpg
```

---

## Deployment Modes

MCPG supports two deployment topologies. The chart auto-wires the correct backends based on your configuration.

### Single-Instance

Default. All state is in-memory, delivery bus is in-process. Suitable for development and low-traffic production with acceptable restart-on-failure semantics.

```yaml
replicaCount: 1
# No NATS or Redis needed — stores default to memory
```

### Multi-Instance

Requires a distributed backend for session/pipeline/task stores and the delivery bus. Without one, server-initiated messages (elicitation, sampling, pipeline suspend/resume) only reach the local instance.

**Option A — Bundled NATS (recommended)**

Deploys a NATS server as a subchart with JetStream enabled for KV storage.

```yaml
replicaCount: 3
nats:
  enabled: true
  config:
    jetstream:
      enabled: true
      memoryStore:
        maxSize: 256Mi
      fileStore:
        maxSize: 1Gi
```

**Option B — Bundled Redis**

Deploys a Redis instance as a subchart.

```yaml
replicaCount: 3
redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: false
  master:
    persistence:
      enabled: true
      size: 1Gi
```

**Option C — External NATS**

Connect to an existing NATS cluster.

```yaml
replicaCount: 3
externalNats:
  enabled: true
  url: "tls://nats.prod.internal:4222"
  credentialsPath: "/etc/nats/creds"
  kvBucket: "mcpg_sessions"
  kvKeyPrefix: "mcpg"
```

**Option D — External Redis**

Connect to an existing Redis instance.

```yaml
replicaCount: 3
externalRedis:
  enabled: true
  url: "rediss://redis.prod.internal:6380"
  keyPrefix: "mcpg"
  poolSize: 8
  existingSecret: "redis-credentials"
  existingSecretKey: "redis-password"
```

### Backend Auto-Wiring

When a distributed backend is available (bundled subchart or external), the chart automatically renders the top-level `cluster:` block. Every capability — sessions, pipelines, tasks, subscriptions, delivery, cancellation — inherits the cluster plugin's connection (Phase 6c-10, 2026-05-02).

```yaml
nats:
  enabled: true        # → renders `cluster: { kind: nats, servers: [nats://nats:4222] }`
# OR:
redis:
  enabled: true        # → renders `cluster: { kind: redis, url: redis://redis:6379, key_prefix: mcpg:cluster: }`
# OR external:
externalNats:
  enabled: true
  url: "nats://nats.prod.internal:4222"
```

**Per-capability override** is now in-process only (`memory` / `file`). It exists to pin a specific capability away from the cluster — e.g., session state on local disk instead of redis:

```yaml
extraConfig:
  mcp:
    configurations:
      sessions:
        store:
          kind: file
          dir: /var/lib/mcpg/sessions
```

For redis or nats capability state, set `cluster.kind` once — operators cannot open per-capability redis / nats connections in-gateway. The previous `storeBackend.{sessionStore,pipelineStore,taskStore}` knobs are gone.

**Custom cluster config** (consul, etcd, TLS, replicas, lease TTLs, …) goes under `extraConfig.cluster:`:

```yaml
extraConfig:
  cluster:
    kind: redis
    url: rediss://redis-cluster.svc:6380
    key_prefix: mcpg:prod:
    lease_ttl_ms: 60000
    peer_ttl_ms: 90000
```

---

## MCPG Configuration

The `config` block in values.yaml is rendered verbatim as `/etc/mcpg/config.yaml`. See the [configuration reference](https://mcpg.dev/docs/gateway/docs/configuration.md) for all options.

```yaml
config:
  gateway:
    server:
      bind_address: "0.0.0.0:8787"
      mcp_path: /mcp
      health_path: /health
      allowed_origins:
        - "https://app.example.com"
      session_idle_timeout_ms: 900_000

  observability:
    enabled: true
    logs:
      enabled: true
      level: info
      sinks:
        - kind: stderr
          config:
            format: json
    metrics:
      enabled: true
      sinks:
        - kind: prometheus
          config:
            path: /metrics

  governance:
    policy:
      tool_access:
        default_minimum_trust: verified
        rules:
          - tool_name: "public.*"
            minimum_trust: unauthenticated

    access:
      oidc_oauth:
        token_source:
          kind: authorization_bearer
        providers:
          - issuer: "https://login.example.com/"
            audiences: ["mcpg"]
            verification:
              kind: oidc_jwks
              allowed_algs: ["RS256"]

  mcp:
    capabilities:
      tools:
        - name: weather.get_forecast
          description: Get weather forecast
          backend:
            kind: http
            url: http://weather-svc:8080/api/forecast
            method: post
            timeout_ms: 5000
```

The `extraConfig` block is deep-merged on top and can be used to set advanced fields or force-override auto-wired values (nats, redis, store sections):

```yaml
extraConfig:
  guardrails:
    pre_execution:
      - name: content_scanner
        url: http://scanner:8080/scan
        timeout_ms: 3000
        on_error: deny
```

### Environment Variable Overrides

Any mcpg config field can be overridden via environment variables with the `MCPG_` prefix and `__` separator for nested keys:

```yaml
extraEnv:
  - name: MCPG_OBSERVABILITY__LOGS__LEVEL
    value: debug
  - name: MCPG_GATEWAY__SERVER__SESSION_IDLE_TIMEOUT_MS
    value: "1800000"
  - name: MPP_SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: mcpg-payment-secrets
        key: mpp-secret
```

---

## Parameters

### Image

The reference is composed as `<registry>/<repositoryPrefix>/<repository>:<tag>`,
so the default resolves to `ghcr.io/mcpg-dev/source-code/gateway:<appVersion>`.
The two `global.image.*` keys are what an air-gapped or mirrored install
repoints; Helm merges `global` into subcharts, so an umbrella chart sets them
once for every mcpg chart underneath it.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.image.registry` | Registry host for first-party images | unset (helper default `ghcr.io`) |
| `global.image.repositoryPrefix` | Registry namespace + path the image name is joined onto | `mcpg-dev/source-code` |
| `image.repository` | Container image NAME. A value containing a `/` is treated as an already-qualified repository and the prefix is not prepended. | `gateway` |
| `image.registry` | Per-chart registry host; overrides `global.image.registry` | unset |
| `image.tag` | Container image tag | `""` (uses `.Chart.AppVersion`) |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets | `[]` |

Setting `global.image.registry` also moves the bundled NATS images: the nats
subchart reads that same key as its own registry override. The bundled Redis
and PostgreSQL subcharts use `global.imageRegistry` instead and are unaffected.
`global.image.repositoryPrefix` is read only by mcpg's own helpers, so it never
touches a third-party image.

### Deployment

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `nameOverride` | Override chart name | `""` |
| `fullnameOverride` | Override full release name | `""` |
| `terminationGracePeriodSeconds` | Pod termination grace period | `30` |
| `priorityClassName` | Pod priority class | `""` |

### Service Account

| Parameter | Description | Default |
|-----------|-------------|---------|
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `serviceAccount.annotations` | ServiceAccount annotations | `{}` |
| `serviceAccount.name` | ServiceAccount name | `""` (generated) |
| `serviceAccount.automountServiceAccountToken` | Automount token | `false` |

### Service

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Service type | `ClusterIP` |
| `service.port` | Service port | `8787` |
| `service.nodePort` | NodePort (when type=NodePort) | `""` |
| `service.annotations` | Service annotations | `{}` |

### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable Ingress | `false` |
| `ingress.className` | Ingress class | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts/paths | `[{host: mcpg.example.com, paths: [{path: /, pathType: Prefix}]}]` |
| `ingress.tls` | TLS configuration | `[]` |

### Autoscaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `autoscaling.enabled` | Enable HPA | `false` |
| `autoscaling.minReplicas` | Minimum replicas | `2` |
| `autoscaling.maxReplicas` | Maximum replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | CPU target | `70` |
| `autoscaling.targetMemoryUtilizationPercentage` | Memory target | `80` |
| `autoscaling.customMetrics` | Custom HPA metrics | `[]` |
| `autoscaling.behavior` | HPA scale up/down behavior | `{}` |

### Pod Disruption Budget

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podDisruptionBudget.enabled` | Enable PDB | `false` |
| `podDisruptionBudget.minAvailable` | Minimum available pods | `1` |
| `podDisruptionBudget.maxUnavailable` | Maximum unavailable pods | `""` |

### Security

| Parameter | Description | Default |
|-----------|-------------|---------|
| `podSecurityContext.runAsNonRoot` | Run as non-root | `true` |
| `podSecurityContext.runAsUser` | UID | `65534` |
| `podSecurityContext.fsGroup` | fsGroup | `65534` |
| `podSecurityContext.seccompProfile.type` | Seccomp profile | `RuntimeDefault` |
| `securityContext.readOnlyRootFilesystem` | Read-only root FS | `true` |
| `securityContext.allowPrivilegeEscalation` | Privilege escalation | `false` |
| `securityContext.capabilities.drop` | Dropped capabilities | `[ALL]` |

### Resources

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `resources.limits.cpu` | CPU limit | `2` |
| `resources.limits.memory` | Memory limit | `512Mi` |

### Probes

| Parameter | Description | Default |
|-----------|-------------|---------|
| `livenessProbe.httpGet.path` | Liveness path | `/health` |
| `readinessProbe.httpGet.path` | Readiness path | `/ready` |
| `startupProbe.httpGet.path` | Startup path | `/health` |
| `startupProbe.failureThreshold` | Startup attempts | `12` |

### Scheduling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nodeSelector` | Node selector labels | `{}` |
| `tolerations` | Pod tolerations | `[]` |
| `affinity` | Pod affinity rules | `{}` |
| `topologySpreadConstraints` | Topology spread | `[]` |

### Network Policy

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `networkPolicy.ingressFrom` | Ingress sources | `[]` |
| `networkPolicy.egressTo` | Egress destinations | `[]` |
| `networkPolicy.additionalEgressRules` | Extra egress rules | `[]` |

When a bundled NATS or Redis subchart is enabled, the NetworkPolicy automatically allows egress to their pods.

### Monitoring

| Parameter | Description | Default |
|-----------|-------------|---------|
| `metrics.enabled` | Enable Prometheus metrics | `false` |
| `metrics.serviceMonitor.enabled` | Create ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | Scrape interval | `30s` |
| `metrics.serviceMonitor.labels` | Extra labels | `{}` |
| `metrics.prometheusRule.enabled` | Create PrometheusRule | `false` |
| `metrics.prometheusRule.rules` | Alert rules | `[]` |

### TLS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tls.enabled` | Enable gateway-level TLS | `false` |
| `tls.existingSecret` | Existing TLS Secret name | `""` |
| `tls.minVersion` | Minimum TLS version | `"1.2"` |
| `tls.certBase64` | Inline cert (base64) | `""` |
| `tls.keyBase64` | Inline key (base64) | `""` |

### Persistence

| Parameter | Description | Default |
|-----------|-------------|---------|
| `persistence.enabled` | Enable PVC for file store | `false` |
| `persistence.storageClassName` | Storage class | `""` |
| `persistence.accessModes` | Access modes | `[ReadWriteOnce]` |
| `persistence.size` | Volume size | `1Gi` |
| `persistence.existingClaim` | Existing PVC name | `""` |

### NATS (Bundled Subchart)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nats.enabled` | Deploy bundled NATS | `false` |
| `nats.config.jetstream.enabled` | Enable JetStream | `true` |
| `nats.config.jetstream.memoryStore.maxSize` | JetStream memory | `256Mi` |
| `nats.config.jetstream.fileStore.maxSize` | JetStream disk | `1Gi` |

All [nats-io/nats](https://github.com/nats-io/k8s/tree/main/helm/charts/nats) chart values are accepted under the `nats` key.

### Redis (Bundled Subchart)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `redis.enabled` | Deploy bundled Redis | `false` |
| `redis.architecture` | Redis architecture | `standalone` |
| `redis.auth.enabled` | Enable Redis auth | `false` |
| `redis.master.persistence.enabled` | Enable persistence | `true` |
| `redis.master.persistence.size` | PVC size | `1Gi` |

All [bitnami/redis](https://github.com/bitnami/charts/tree/main/bitnami/redis) chart values are accepted under the `redis` key.

### External NATS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalNats.enabled` | Use external NATS | `false` |
| `externalNats.url` | NATS URL | `"nats://nats.example.com:4222"` |
| `externalNats.credentialsPath` | Credentials file path | `""` |
| `externalNats.kvBucket` | KV bucket name | `"mcpg_sessions"` |
| `externalNats.kvKeyPrefix` | KV key prefix | `"mcpg"` |

### External Redis

| Parameter | Description | Default |
|-----------|-------------|---------|
| `externalRedis.enabled` | Use external Redis | `false` |
| `externalRedis.url` | Redis URL | `"redis://redis.example.com:6379"` |
| `externalRedis.keyPrefix` | Key prefix | `"mcpg"` |
| `externalRedis.poolSize` | Connection pool size | `4` |
| `externalRedis.existingSecret` | Secret with Redis password | `""` |
| `externalRedis.existingSecretKey` | Key in the Secret | `"redis-password"` |

### Cluster Backend (Phase 6c-10)

The chart auto-renders `cluster:` from `nats.enabled` / `redis.enabled` /
`externalNats.enabled` / `externalRedis.enabled`. Operators wanting custom
cluster.kind / TLS / replicas / etc. set `extraConfig.cluster:` — that
merges last and wins.

The pre-6c-10 `storeBackend.{sessionStore,pipelineStore,taskStore}` knobs
are gone — per-capability redis / nats overrides are no longer accepted
in-gateway. Operators wanting an in-process override (memory / file) set
it under `extraConfig.{sessions,pipelines,tasks,subscriptions,delivery,
cancellation}`.

### Extensions

| Parameter | Description | Default |
|-----------|-------------|---------|
| `extraEnv` | Extra environment variables | `[]` |
| `extraEnvFrom` | Extra env from ConfigMap/Secret | `[]` |
| `extraVolumeMounts` | Extra volume mounts | `[]` |
| `extraVolumes` | Extra volumes | `[]` |
| `initContainers` | Init containers | `[]` |
| `sidecars` | Sidecar containers | `[]` |
| `extraConfig` | Extra config merged into config.yaml | `{}` |

---

## Examples

### Production HA with NATS, Ingress, and Monitoring

```yaml
replicaCount: 3

nats:
  enabled: true

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 60

podDisruptionBudget:
  enabled: true
  minAvailable: 2

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: mcp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: mcpg-tls
      hosts:
        - mcp.example.com

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
  prometheusRule:
    enabled: true
    rules:
      - alert: McpgHighErrorRate
        expr: rate(mcpg_binding_executions_total{outcome="error"}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "MCPG error rate above 10%"
      - alert: McpgDown
        expr: up{job="mcpg"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "MCPG instance is down"

networkPolicy:
  enabled: true
  ingressFrom:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: mcpg

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: "4"
    memory: 1Gi

config:
  gateway:
    server:
      bind_address: "0.0.0.0:8787"
      session_idle_timeout_ms: 1_800_000
  observability:
    enabled: true
    logs:
      enabled: true
      level: info
      sinks:
        - kind: stderr
          config:
            format: json
    metrics:
      enabled: true
      sinks:
        - kind: prometheus
          config:
            path: /metrics
    traces:
      enabled: true
      service_name: mcpg
      propagate_context: true
      sinks:
        - kind: otlp
          config:
            url: "http://otel-collector.monitoring:4317"
  governance:
    policy:
      tool_access:
        default_minimum_trust: verified
    access:
      oidc_oauth:
        token_source:
          kind: authorization_bearer
        providers:
          - issuer: "https://login.example.com/"
            audiences: ["mcpg"]
            verification:
              kind: oidc_jwks
              allowed_algs: ["RS256"]
```

### Minimal Development Setup

```yaml
replicaCount: 1

config:
  gateway:
    server:
      bind_address: "0.0.0.0:8787"
  observability:
    enabled: true
    logs:
      enabled: true
      level: debug
      sinks:
        - kind: stderr
          config:
            format: pretty
  governance:
    policy:
      tool_access:
        default_minimum_trust: unauthenticated
  plugins:
    - id: dev.mcpg.backend.mock
      class: backend
      source:
        oci: "ghcr.io/mcpg-dev/source-code/plugins/backend-mock:0.0.1-alpha.10"
  mcp:
    capabilities:
      tools:
        - name: dev.echo
          description: Echo fixture for testing
          backend:
            kind: mock
            response:
              status: ok
              message: "Hello from MCPG"
```

---

## Architecture

```
                        ┌──────────────────────────────────────┐
                        │           Kubernetes Cluster          │
                        │                                      │
  Ingress ──────────────┤──→  Service ──→  Deployment (N pods) │
                        │         │                            │
                        │         │    ┌───── ConfigMap ─────┐ │
                        │         │    │   config.yaml       │ │
                        │         │    └─────────────────────┘ │
                        │         │                            │
                        │         ▼                            │
                        │    ┌─────────┐    ┌──────────────┐  │
                        │    │  mcpg   │◄──►│ NATS / Redis │  │
                        │    │ gateway │    │  (state +    │  │
                        │    │         │    │  delivery)   │  │
                        │    └─────────┘    └──────────────┘  │
                        │         │                            │
                        │    ServiceMonitor ──→ Prometheus     │
                        └──────────────────────────────────────┘
```
