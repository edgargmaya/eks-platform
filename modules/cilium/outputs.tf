output "disable_legacy_cni_status" {
  description = "Helm release status for the aws-node/kube-proxy patch."
  value       = helm_release.disable_legacy_cni.status
}

output "release_name" {
  description = "Helm release name for Cilium."
  value       = helm_release.cilium.name
}

output "chart_version" {
  description = "Installed Cilium Helm chart version."
  value       = helm_release.cilium.version
}

output "namespace" {
  description = "Namespace where Cilium is installed."
  value       = helm_release.cilium.namespace
}

output "status" {
  description = "Helm release status."
  value       = helm_release.cilium.status
}
