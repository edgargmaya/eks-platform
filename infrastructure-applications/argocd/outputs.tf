output "chart_version" {
  description = "Installed argo-cd Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where Argo CD is installed."
  value       = helm_release.this.namespace
}

output "server_service_name" {
  description = "ClusterIP Service for the UI and API. Release name argocd plus the chart nameOverride."
  value       = "argocd-server"
}
