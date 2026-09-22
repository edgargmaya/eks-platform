output "chart_version" {
  description = "Installed metrics-server Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where metrics-server is installed."
  value       = helm_release.this.namespace
}
