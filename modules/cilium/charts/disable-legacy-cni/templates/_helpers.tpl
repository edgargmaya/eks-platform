{{- define "disable-legacy-cni.hookAnnotations" -}}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
{{- end }}

{{- define "disable-legacy-cni.kubectlEnv" -}}
- name: KUBERNETES_SERVICE_HOST
  value: {{ .Values.apiServerHost | quote }}
- name: KUBERNETES_SERVICE_PORT
  value: {{ .Values.apiServerPort | quote }}
- name: KUBERNETES_SERVICE_PORT_HTTPS
  value: {{ .Values.apiServerPort | quote }}
{{- end }}
