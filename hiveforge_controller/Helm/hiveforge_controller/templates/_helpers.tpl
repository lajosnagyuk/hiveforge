{{/*
Retrieve existing master key or generate a new one
*/}}
{{- define "hiveforge.getMasterKey" -}}
{{- $secretName := printf "%s-master-key" .Release.Name -}}
{{- $secretKey := "master-key" -}}
{{- if (lookup "v1" "Secret" .Release.Namespace $secretName) }}
    {{- index (lookup "v1" "Secret" .Release.Namespace $secretName).data $secretKey }}
{{- else }}
    {{- default (randAlphaNum 32 | b64enc) .Values.masterKey | b64enc }}
{{- end }}
{{- end }}
