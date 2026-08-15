{{/*
Expand the name of the chart.
*/}}
{{- define "mcpg.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "mcpg.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mcpg.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mcpg.labels" -}}
helm.sh/chart: {{ include "mcpg.chart" . }}
{{ include "mcpg.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mcpg
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mcpg.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcpg.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mcpg.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mcpg.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Container image reference, composed from the global OCI coordinates so one
setting repoints every first-party image:

  global.image.registry          registry host     ghcr.io
  global.image.repositoryPrefix  namespace + path  mcpg-dev/source-code
  image.repository               image NAME        gateway

Registry host precedence, lowest first: the built-in `ghcr.io`, then
`global.image.registry`, then this chart's own `image.registry`. A key that is
PRESENT but empty means "no host" and renders a host-less reference, the same
"set but empty means none" rule MCPG_OCI_PATH follows in
docs/release/OCI-REGISTRY-CONFIGURATION.md — which is why each level is tested
with `hasKey` rather than for truthiness.

An `image.repository` containing a `/` is a fully-qualified repository:
`repositoryPrefix` is not prepended, so a chart can address a path outside the
prefix layout.
*/}}
{{- define "mcpg.image" -}}
{{- $global := (.Values.global | default dict).image | default dict -}}
{{- $registry := "ghcr.io" -}}
{{- if hasKey $global "registry" -}}
{{- $registry = $global.registry -}}
{{- end -}}
{{- if hasKey .Values.image "registry" -}}
{{- $registry = .Values.image.registry -}}
{{- end -}}
{{- $repository := .Values.image.repository -}}
{{- if and (not (contains "/" $repository)) $global.repositoryPrefix -}}
{{- $repository = printf "%s/%s" $global.repositoryPrefix $repository -}}
{{- end -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- if $registry -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Config checksum annotation — triggers rolling restart on config change
*/}}
{{- define "mcpg.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- end }}

{{/* ======================================================================
     Distributed backend detection helpers
     ====================================================================== */}}

{{/*
Determine if NATS is available (bundled subchart OR external).
Returns "true" or "".
*/}}
{{- define "mcpg.natsAvailable" -}}
{{- if or .Values.nats.enabled .Values.externalNats.enabled -}}
true
{{- end -}}
{{- end }}

{{/*
Determine if Redis is available (bundled subchart OR external).
Returns "true" or "".
*/}}
{{- define "mcpg.redisAvailable" -}}
{{- if or .Values.redis.enabled .Values.externalRedis.enabled -}}
true
{{- end -}}
{{- end }}

{{/*
Determine if multi-instance deployment is requested.
True when replicaCount > 1 OR autoscaling is enabled.
*/}}
{{- define "mcpg.isMultiInstance" -}}
{{- if or .Values.autoscaling.enabled (gt (int .Values.replicaCount) 1) -}}
true
{{- end -}}
{{- end }}

{{/*
Resolve the NATS URL.
  - Bundled subchart: nats://<release>-nats:4222
  - External: externalNats.url
*/}}
{{- define "mcpg.natsUrl" -}}
{{- if .Values.nats.enabled -}}
nats://{{ include "mcpg.fullname" . }}-nats:4222
{{- else if .Values.externalNats.enabled -}}
{{ .Values.externalNats.url }}
{{- end -}}
{{- end }}

{{/*
Resolve the Redis URL.
  - Bundled subchart: redis(s)://<release>-redis-master:6379
    (rediss:// when the bundled redis has tls.enabled).
  - External: externalRedis.url verbatim (operator controls the scheme).
*/}}
{{- define "mcpg.redisUrl" -}}
{{- if .Values.redis.enabled -}}
{{- $scheme := "redis" -}}
{{- if ((.Values.redis.tls).enabled) -}}{{- $scheme = "rediss" -}}{{- end -}}
{{ $scheme }}://{{ include "mcpg.fullname" . }}-redis-master:6379
{{- else if .Values.externalRedis.enabled -}}
{{ .Values.externalRedis.url }}
{{- end -}}
{{- end }}

{{/*
Bundled-Redis auth Secret name + password key.

Must match how the bitnami/redis subchart names its OWN generated Secret
(`common.names.fullname` in the subchart's context = `<release>-redis`),
NOT `mcpg.fullname`-derived — otherwise the secretKeyRef points at a
non-existent Secret and the pod fails with CreateContainerConfigError.
`common.names.dependency.fullname` resolves the subchart's name from the
parent context. Honours `redis.auth.existingSecret` like the subchart does.
*/}}
{{- define "mcpg.bundledRedisSecretName" -}}
{{- if .Values.redis.auth.existingSecret -}}
{{- tpl .Values.redis.auth.existingSecret $ -}}
{{- else -}}
{{- include "common.names.dependency.fullname" (dict "chartName" "redis" "chartValues" .Values.redis "context" $) -}}
{{- end -}}
{{- end }}
{{- define "mcpg.bundledRedisSecretPasswordKey" -}}
{{- if and .Values.redis.auth.existingSecret .Values.redis.auth.existingSecretPasswordKey -}}
{{- tpl .Values.redis.auth.existingSecretPasswordKey $ -}}
{{- else -}}
redis-password
{{- end -}}
{{- end }}

{{/*
Phase 6c-10 dropped the per-capability `kind: redis | nats` override
and the chart's storeBackend knobs that drove it. Operators set
`cluster.kind` once at the top level (auto-rendered from
nats.enabled / redis.enabled by configmap.yaml) and every capability
inherits the connection. This helper is preserved as a stub for any
out-of-tree consumers that still call it; it now always returns
"memory" — meaning "no per-cap override; inherit from cluster.kind".
*/}}
{{- define "mcpg.resolveStoreKind" -}}
memory
{{- end }}

{{/*
Resolve the Prometheus metrics path from the first prometheus sink
configured under .Values.config.observability.metrics.sinks. Defaults
to "/metrics" when no prometheus sink is declared. Mirrors the
gateway's first-sink-of-kind extraction in observability::init.
*/}}
{{- define "mcpg.metricsPath" -}}
{{- $path := "/metrics" -}}
{{- $found := false -}}
{{- range (((.Values.config.observability).metrics).sinks | default list) -}}
  {{- if not $found -}}
    {{- if eq (.kind | default "") "prometheus" -}}
      {{- $path = ((.config | default dict).path | default "/metrics") -}}
      {{- $found = true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $path -}}
{{- end }}

{{/*
Registry the gateway resolves bare plugin references against, composed from the
same global coordinates as the gateway image so one setting repoints both the
image and the plugins it pulls.

Renders empty when the composition equals the gateway's compiled-in default, so
an install that has not moved its registry emits no env var. The literal below
is the `internal` channel of tools/release/oci-registry.json;
selftest-oci-registry asserts the two agree.

An explicit `config.plugin_registry.default_registry` still wins: the gateway
resolves YAML above the environment.
*/}}
{{- define "mcpg.pluginRegistry" -}}
{{- $builtin := "ghcr.io/mcpg-dev/source-code/plugins" -}}
{{- $global := (.Values.global | default dict).image | default dict -}}
{{- $ref := "" -}}
{{- if or (hasKey $global "registry") $global.repositoryPrefix -}}
{{- $registry := "ghcr.io" -}}
{{- if hasKey $global "registry" -}}
{{- $registry = $global.registry -}}
{{- end -}}
{{- $repository := "plugins" -}}
{{- if $global.repositoryPrefix -}}
{{- $repository = printf "%s/%s" $global.repositoryPrefix $repository -}}
{{- end -}}
{{- if $registry -}}
{{- $ref = printf "%s/%s" $registry $repository -}}
{{- else -}}
{{- $ref = $repository -}}
{{- end -}}
{{- end -}}
{{- if ne $ref $builtin -}}
{{- $ref -}}
{{- end -}}
{{- end }}
