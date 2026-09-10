output "operator_role_arn" {
  description = "IAM role ARN annotated on keda-operator via IRSA."
  value       = aws_iam_role.operator.arn
}

output "operator_role_name" {
  description = "IAM role name for the KEDA operator."
  value       = aws_iam_role.operator.name
}

output "chart_version" {
  description = "Installed KEDA Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where KEDA is installed."
  value       = helm_release.this.namespace
}
