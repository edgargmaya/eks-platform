output "operator_role_name" {
  description = "IAM role name assumed by cilium-operator via IRSA."
  value       = aws_iam_role.operator.name
}

output "operator_role_arn" {
  description = "IRSA role ARN annotated on the cilium-operator service account."
  value       = aws_iam_role.operator.arn
}

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
  description = "Cilium Helm release status."
  value       = helm_release.cilium.status
}
