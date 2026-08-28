output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "node_group_arn" {
  description = "Managed node group ARN."
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Managed node group status."
  value       = aws_eks_node_group.this.status
}

output "ami_id" {
  description = "AMI ID used by the launch template (SSM recommended or override)."
  value       = local.ami_id
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = aws_launch_template.this.id
}
