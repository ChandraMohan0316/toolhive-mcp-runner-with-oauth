{{/*
All resource names are prefixed with .Release.Name to avoid conflicts
with other deployments in the same namespace.
*/}}

{{- define "toolhive-mcp.serverName" -}}
{{ .Release.Name }}-mcp-server
{{- end }}

{{- define "toolhive-mcp.secretBearerName" -}}
{{ .Release.Name }}-bearer-token
{{- end }}

{{- define "toolhive-mcp.secretAzureName" -}}
{{ .Release.Name }}-azure-ad-credentials
{{- end }}

{{- define "toolhive-mcp.authConfigName" -}}
{{ .Release.Name }}-azure-ad-auth
{{- end }}

{{- define "toolhive-mcp.proxyName" -}}
{{ .Release.Name }}-proxy
{{- end }}

{{- define "toolhive-mcp.proxyServiceName" -}}
mcp-{{ .Release.Name }}-proxy-remote-proxy
{{- end }}

{{- define "toolhive-mcp.ingressName" -}}
{{ .Release.Name }}-ingress
{{- end }}

{{/*
Strip scheme from host value — handles both "https://host" and "host"
*/}}
{{- define "toolhive-mcp.host" -}}
{{- .Values.ingress.host | trimPrefix "https://" | trimPrefix "http://" -}}
{{- end }}

{{- define "toolhive-mcp.issuerUrl" -}}
https://{{ include "toolhive-mcp.host" . }}
{{- end }}

{{- define "toolhive-mcp.redirectUri" -}}
https://{{ include "toolhive-mcp.host" . }}/oauth/callback
{{- end }}

{{- define "toolhive-mcp.resourceUrl" -}}
https://{{ include "toolhive-mcp.host" . }}/mcp
{{- end }}

{{- define "toolhive-mcp.azureIssuerUrl" -}}
https://login.microsoftonline.com/{{ .Values.oauth.azure.tenantId }}/v2.0
{{- end }}

{{/*
Common labels
*/}}
{{- define "toolhive-mcp.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
