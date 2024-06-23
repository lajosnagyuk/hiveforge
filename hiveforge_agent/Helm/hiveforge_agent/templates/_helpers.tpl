{{- define "checkCertSecret" }}
{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace (printf "%s-cert-secret" .Release.Name) }}
{{- $existingCert := "" }}
{{- if $existingSecret }}
  {{- $existingCert = index $existingSecret.data "ca-cert.pem" | default "" }}
{{- end }}
{{- $newCert := .Values.tunables.certificates.cacertfile | default "" }}

{{- if eq (lower .Values.tunables.certificates.cacertfileMountEnabled) "true" }}
  {{- if or (not $existingCert) $newCert }}
    {{- $newCertEncoded := $newCert }}
    {{- if not (regexMatch "^[-A-Za-z0-9+/]*={0,3}$" $newCert) }}
      {{- $newCertEncoded = $newCert | b64enc }}
    {{- end }}
# secret file for ca-cert.pem
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-cert-secret
type: Opaque
data:
  ca-cert.pem: {{ $newCertEncoded | default $existingCert }}
  {{- end }}
{{- end }}
{{- end }}
