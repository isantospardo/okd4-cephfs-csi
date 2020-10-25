{{/*
We decided to add the clusterName to the driverName as we currently do not have the possibility of distinguish PVCs created for other clusters
Once this issue https://github.com/kubernetes/cloud-provider-openstack/issues/1280 is implemented, we will be able to remove this part and really
in adding specific metadata for each manila share
*/}}

{{- define "cephfscsi.drivername" -}}
{{ .Values.global.clusterName }}.manila-csi-provisioner
{{- end -}}
