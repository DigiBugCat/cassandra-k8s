{{- define "registry.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "registry.labels" -}}
app.kubernetes.io/name: registry
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "registry.selectorLabels" -}}
app.kubernetes.io/name: registry
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
