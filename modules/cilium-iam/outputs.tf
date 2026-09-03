output "operator_role_name" {
  description = "IAM role name assumed by cilium-operator via IRSA."
  value       = aws_iam_role.operator.name
}

output "operator_role_arn" {
  description = "IAM role ARN annotated on the cilium-operator service account."
  value       = aws_iam_role.operator.arn
}

output "service_account_name" {
  description = "Service account name the role is trusted for."
  value       = var.service_account_name
}

output "namespace" {
  description = "Namespace of the cilium-operator service account."
  value       = var.namespace
}
