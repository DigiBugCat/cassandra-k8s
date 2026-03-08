{{- define "cassandra-yt-mcp.name" -}}
cassandra-yt-mcp
{{- end -}}

{{- define "cassandra-yt-mcp.fullname" -}}
cassandra-yt-mcp
{{- end -}}

{{- define "cassandra-yt-mcp.labels" -}}
app.kubernetes.io/name: {{ include "cassandra-yt-mcp.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "cassandra-yt-mcp.selectorLabels" -}}
app: {{ include "cassandra-yt-mcp.fullname" . }}
{{- end -}}
