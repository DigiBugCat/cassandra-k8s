{{- define "claude-runner.name" -}}
claude-runner
{{- end -}}

{{- define "claude-runner.orchestratorName" -}}
claude-orchestrator
{{- end -}}

{{- define "claude-runner.labels" -}}
app.kubernetes.io/name: {{ include "claude-runner.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "claude-runner.orchestratorLabels" -}}
app: {{ include "claude-runner.orchestratorName" . }}
{{ include "claude-runner.labels" . }}
{{- end -}}

{{- define "claude-runner.selectorLabels" -}}
app: {{ include "claude-runner.orchestratorName" . }}
{{- end -}}
