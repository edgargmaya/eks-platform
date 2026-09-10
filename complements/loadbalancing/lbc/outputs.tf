output "controller_role_arn" {
  description = "IAM role ARN annotated on aws-load-balancer-controller via IRSA."
  value       = aws_iam_role.controller.arn
}

output "controller_role_name" {
  description = "IAM role name for the AWS Load Balancer Controller."
  value       = aws_iam_role.controller.name
}

output "controller_policy_arn" {
  description = "Customer-managed IAM policy ARN attached to the controller role."
  value       = aws_iam_policy.controller.arn
}

output "chart_version" {
  description = "Installed aws-load-balancer-controller Helm chart version."
  value       = helm_release.this.version
}

output "status" {
  description = "Helm release status."
  value       = helm_release.this.status
}

output "ingress_class" {
  description = "IngressClass name the controller owns."
  value       = var.ingress_class
}
