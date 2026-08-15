{{/*
Helper templates for the mcpg-operator chart.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "mcpg-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name. Falls back to release name + chart name.
*/}}
{{- define "mcpg-operator.fullname" -}}
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

{{/*
Standard labels.
*/}}
{{- define "mcpg-operator.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "mcpg-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: mcpg
{{- end -}}

{{/*
Selector labels (subset of standard, omits version + helm.sh/chart
so rolling upgrades don't break the selector).
*/}}
{{- define "mcpg-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mcpg-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name to use.
*/}}
{{- define "mcpg-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "mcpg-operator.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Webhook Service name.
*/}}
{{- define "mcpg-operator.webhookServiceName" -}}
{{- printf "%s-webhook" (include "mcpg-operator.fullname" .) -}}
{{- end -}}

{{/*
Webhook TLS secret name.
*/}}
{{- define "mcpg-operator.webhookSecretName" -}}
{{- if .Values.certManager.enabled -}}
{{- printf "%s-webhook-tls" (include "mcpg-operator.fullname" .) -}}
{{- else -}}
{{- .Values.tls.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Image reference, composed from the global OCI coordinates so one setting
repoints every first-party image:

  global.image.registry          registry host     ghcr.io
  global.image.repositoryPrefix  namespace + path  mcpg-dev/source-code
  image.repository               image NAME        mcpg-operator

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
{{- define "mcpg-operator.image" -}}
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
Repository (no tag) the operator falls back to for gateways whose CR omits
`spec.image.repository`, composed from the same coordinates as the operator's
own image so one setting repoints both.

Renders empty when the composition equals the operator's compiled-in default,
so an install that has not moved its registry emits no env var and existing
pods are not restarted by an upgrade that changes nothing. The literal below is
the `internal` channel of tools/release/oci-registry.json; selftest-oci-registry
asserts the two agree.
*/}}
{{- define "mcpg-operator.gatewayImageRepository" -}}
{{- $builtin := "ghcr.io/mcpg-dev/source-code/gateway" -}}
{{- $global := (.Values.global | default dict).image | default dict -}}
{{- $ref := "" -}}
{{- if or (hasKey $global "registry") $global.repositoryPrefix -}}
{{- $registry := "ghcr.io" -}}
{{- if hasKey $global "registry" -}}
{{- $registry = $global.registry -}}
{{- end -}}
{{- $repository := .Values.operator.gatewayImageName -}}
{{- if and (not (contains "/" $repository)) $global.repositoryPrefix -}}
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
{{- end -}}

{{/*
Namespace every namespaced object renders into. The operator hard-codes
`mcpg-system` for its plugin-Secret writes and tenant RoleBindings, so an
umbrella chart installing from another namespace sets `namespaceOverride`
to place the operator (and everything that must sit next to it — webhook
Service, TLS Certificate, lease) there.
*/}}
{{- define "mcpg-operator.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}
