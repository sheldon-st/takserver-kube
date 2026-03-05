{{/*
Common labels
*/}}
{{- define "tak-server.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Fullname helper
*/}}
{{- define "tak-server.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
