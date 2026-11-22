{{/*
Common labels
*/}}
{{- define "tak-server.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: tak-server
{{- end }}

{{/*
Fullname helper
*/}}
{{- define "tak-server.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
