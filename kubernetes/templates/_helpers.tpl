{{/*
Expand the name of the chart.
*/}}
{{- define "mirador-pipelines.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mirador-pipelines.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mirador-pipelines.labels" -}}
helm.sh/chart: {{ include "mirador-pipelines.chart" . }}
app.kubernetes.io/name: {{ include "mirador-pipelines.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
