{{- define "wyoming.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "wyoming.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "wyoming.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "wyoming.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ include "wyoming.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Resource block merging user resources with HAMI GPU requests.
Usage: {{ include "wyoming.resources" .Values.whisper | nindent 12 }}
*/}}
{{- define "wyoming.resources" -}}
{{- $res := deepCopy (default (dict) .resources) -}}
{{- if .gpu.enabled -}}
  {{- $lim := default (dict) $res.limits -}}
  {{- $req := default (dict) $res.requests -}}
  {{- $_ := set $lim "nvidia.com/gpu" (.gpu.count | int) -}}
  {{- $_ := set $req "nvidia.com/gpu" (.gpu.count | int) -}}
  {{- if .gpu.memoryMiB -}}
    {{- $_ := set $lim "nvidia.com/gpumem" (.gpu.memoryMiB | int) -}}
    {{- $_ := set $req "nvidia.com/gpumem" (.gpu.memoryMiB | int) -}}
  {{- end -}}
  {{- $_ := set $res "limits" $lim -}}
  {{- $_ := set $res "requests" $req -}}
{{- end -}}
{{- if $res -}}
{{ toYaml $res }}
{{- else -}}
{}
{{- end -}}
{{- end -}}
