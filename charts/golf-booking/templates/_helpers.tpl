{{- define "golf.labels" -}}
app.kubernetes.io/part-of: golf-booking
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "golf.image" -}}
{{- $root := index . 0 -}}{{- $name := index . 1 -}}
{{- required "image.registry is required" $root.Values.image.registry }}/golf-booking/{{ $name }}:{{ required "image.tag is required" $root.Values.image.tag }}
{{- end -}}
