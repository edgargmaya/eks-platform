output "controller_role_arn" {
  description = "IAM role ARN annotated on the karpenter service account via IRSA."
  value       = aws_iam_role.controller.arn
}

output "controller_role_name" {
  description = "IAM role name for the Karpenter controller."
  value       = aws_iam_role.controller.name
}

output "node_instance_profile_name" {
  description = "Instance profile Karpenter attaches to launched nodes."
  value       = aws_iam_instance_profile.nodes.name
}

output "interruption_queue_name" {
  description = "SQS queue Karpenter consumes for EC2 interruption events."
  value       = aws_sqs_queue.interruption.name
}

output "chart_version" {
  description = "Installed Karpenter Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Karpenter Helm release status."
  value       = helm_release.this.status
}

output "namespace" {
  description = "Namespace where Karpenter is installed."
  value       = helm_release.this.namespace
}
