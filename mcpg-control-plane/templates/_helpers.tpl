{{/*
Expand the name of the chart.
*/}}
{{- define "mcpg-cp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Generate a fully-qualified app name (release-name + chart-name unless
overridden). Truncated to fit DNS-1035 label rules.
*/}}
{{- define "mcpg-cp.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "mcpg-cp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mcpg-cp.labels" -}}
helm.sh/chart: {{ include "mcpg-cp.chart" . }}
{{ include "mcpg-cp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: control-plane
{{- end -}}

{{- define "mcpg-cp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcpg-cp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mcpg-cp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ default (include "mcpg-cp.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Container image reference, composed from the global OCI coordinates so one
setting repoints every first-party image:

  global.image.registry          registry host     ghcr.io
  global.image.repositoryPrefix  namespace + path  mcpg-dev/source-code
  image.repository               image NAME        mcpg-control-plane-server

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
{{- define "mcpg-cp.image" -}}
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
{{- end -}}

{{/*
Resolve the database URL. Precedence:
  1. cp.dbUrl explicitly set → use as-is.
  2. postgresql sub-chart enabled → derive from sub-chart.
  3. externalDatabase enabled → derive from those values.
  4. Default to SQLite under /var/lib/mcpg-cp/state.db.
*/}}
{{- define "mcpg-cp.dbUrl" -}}
{{- if .Values.cp.dbUrl -}}
{{ .Values.cp.dbUrl }}
{{- else if .Values.postgresql.enabled -}}
{{- /* The password is delivered as MCPG_CP_DB_PASSWORD (declared earlier in
       the env list) and spliced in via Kubernetes dependent-env expansion —
       the binary reads only the full DSN. */ -}}
postgresql://{{ .Values.postgresql.auth.username }}:$(MCPG_CP_DB_PASSWORD)@{{ .Release.Name }}-postgresql:5432/{{ .Values.postgresql.auth.database }}
{{- else if .Values.externalDatabase.enabled -}}
{{- if .Values.externalDatabase.existingSecret -}}
postgresql://{{ .Values.externalDatabase.username }}:$(MCPG_CP_DB_PASSWORD)@{{ .Values.externalDatabase.host }}:{{ .Values.externalDatabase.port }}/{{ .Values.externalDatabase.database }}
{{- else -}}
postgresql://{{ .Values.externalDatabase.username }}@{{ .Values.externalDatabase.host }}:{{ .Values.externalDatabase.port }}/{{ .Values.externalDatabase.database }}
{{- end -}}
{{- else -}}
sqlite:///var/lib/mcpg-cp/state.db?mode=rwc
{{- end -}}
{{- end -}}

{{/*
Non-empty when the chart can see a shared-database configuration that
supports multiple replicas: a non-sqlite cp.dbUrl, the bundled Postgres
sub-chart, an external database, or the declaration that a Postgres DSN
arrives via extraEnv/extraEnvFrom (cp.assumeExternalDbUrl). The sqlite
default (and an explicit sqlite cp.dbUrl) yields "", which drives the
Recreate strategy and the replicaCount > 1 render guard.
*/}}
{{- define "mcpg-cp.sharedDb" -}}
{{- if or .Values.postgresql.enabled .Values.externalDatabase.enabled .Values.cp.assumeExternalDbUrl -}}
true
{{- else if and .Values.cp.dbUrl (not (hasPrefix "sqlite" .Values.cp.dbUrl)) -}}
true
{{- end -}}
{{- end -}}
