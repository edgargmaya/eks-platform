output "cluster_role_name" {
  description = "IAM role name assumed by the EKS control plane."
  value       = aws_iam_role.cluster.name
}

output "cluster_role_arn" {
  description = "IAM role ARN assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_role_name" {
  description = "IAM role name assumed by worker nodes."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "IAM role ARN assumed by worker nodes."
  value       = aws_iam_role.node.arn
}
