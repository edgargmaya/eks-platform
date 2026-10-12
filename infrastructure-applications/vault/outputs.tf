output "chart_version" {
  description = "Installed Vault Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status. The StatefulSet stays unready until operator init."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where Vault is installed."
  value       = helm_release.this.namespace
}

output "unseal_key_arn" {
  description = "KMS key ARN used by the awskms seal."
  value       = aws_kms_key.unseal.arn
}

output "server_role_arn" {
  description = "IAM role ARN annotated on the Vault ServiceAccount."
  value       = aws_iam_role.server.arn
}

output "node_pool_name" {
  description = "Karpenter NodePool dedicated to Vault."
  value       = var.node_pool_name
}
