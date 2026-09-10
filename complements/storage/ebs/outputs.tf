output "controller_role_arn" {
  description = "IAM role ARN annotated on ebs-csi-controller-sa via IRSA."
  value       = aws_iam_role.controller.arn
}

output "controller_role_name" {
  description = "IAM role name for the EBS CSI controller."
  value       = aws_iam_role.controller.name
}

output "ebs_csi_addon_version" {
  description = "Installed aws-ebs-csi-driver add-on version."
  value       = aws_eks_addon.ebs_csi.addon_version
}

output "ebs_csi_addon_arn" {
  description = "ARN of the aws-ebs-csi-driver EKS add-on."
  value       = aws_eks_addon.ebs_csi.arn
}

output "storage_class_name" {
  description = "Name of the gp3 StorageClass."
  value       = var.storage_class_name
}
