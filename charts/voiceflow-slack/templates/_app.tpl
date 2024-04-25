{{/*
app env settings
*/}}
{{- define "app.settings" -}}
- name: VOICEFLOW_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "voiceflow-slack.fullname" . }}
      key: voiceflow-api-key
{{- with .Values.settings.voiceflow }}
- name: VOICEFLOW_VERSION_ID
  value: {{ .version_id | quote }}
- name: VOICEFLOW_PROJECT_ID
  value: {{ .project_id | quote }}
- name: VOICEFLOW_RUNTIME_ENDPOINT
  value: {{ .runtime_endpoint | quote }}
{{- end }}
- name: SLACK_APP_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "voiceflow-slack.fullname" . }}
      key: slack-app-token
- name: SLACK_BOT_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "voiceflow-slack.fullname" . }}
      key: slack-bot-token
- name: SLACK_SIGNING_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "voiceflow-slack.fullname" . }}
      key: slack-signing-secret
{{- end -}}
