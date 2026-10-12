output "chart_version" {
  description = "Installed External Secrets Operator Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where External Secrets Operator is installed."
  value       = helm_release.this.namespace
}
