output "cluster_name" {
  description = "EKS cluster name."
  value       = module.cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.cluster.cluster_endpoint
}

output "cluster_version" {
  description = "Kubernetes version reported by EKS."
  value       = module.cluster.cluster_version
}

output "cluster_security_group_id" {
  description = "Cluster security group created by EKS."
  value       = module.cluster.cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = module.cluster.oidc_provider_arn
}

output "oidc_provider_hostpath" {
  description = "OIDC issuer without https://, for IAM trust conditions."
  value       = module.cluster.oidc_provider_hostpath
}

output "cluster_role_arn" {
  description = "IAM role ARN assumed by the control plane."
  value       = module.iam.cluster_role_arn
}

output "node_role_arn" {
  description = "IAM role ARN assumed by worker nodes."
  value       = module.iam.node_role_arn
}

output "node_group_name" {
  description = "Default managed node group name."
  value       = module.nodegroup.node_group_name
}

output "node_ami_id" {
  description = "AMI ID resolved for the default node group."
  value       = module.nodegroup.ami_id
}

output "kms_key_arn" {
  description = "CMK used for secrets encryption and control-plane logs."
  value       = module.cluster.kms_key_arn
}

output "configure_kubectl" {
  description = "Command to write kubeconfig for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.cluster.cluster_name}"
}

output "cilium_operator_role_arn" {
  description = "IRSA role ARN used by cilium-operator for ENI IPAM."
  value       = module.cilium.operator_role_arn
}

output "cilium_chart_version" {
  description = "Installed Cilium Helm chart version."
  value       = module.cilium.chart_version
}

output "cilium_status" {
  description = "Cilium Helm release status."
  value       = module.cilium.status
}

output "ebs_csi_controller_role_arn" {
  description = "IAM role ARN for ebs-csi-controller-sa (IRSA)."
  value       = module.ebs.controller_role_arn
}

output "ebs_csi_addon_version" {
  description = "Installed aws-ebs-csi-driver add-on version."
  value       = module.ebs.ebs_csi_addon_version
}

output "ebs_csi_addon_arn" {
  description = "ARN of the aws-ebs-csi-driver EKS add-on."
  value       = module.ebs.ebs_csi_addon_arn
}

output "ebs_storage_class_name" {
  description = "Default gp3 StorageClass name."
  value       = module.ebs.storage_class_name
}

output "lbc_controller_role_arn" {
  description = "IAM role ARN for aws-load-balancer-controller (IRSA)."
  value       = module.lbc.controller_role_arn
}

output "lbc_chart_version" {
  description = "Installed AWS Load Balancer Controller Helm chart version."
  value       = module.lbc.chart_version
}

output "lbc_status" {
  description = "AWS Load Balancer Controller Helm release status."
  value       = module.lbc.status
}

output "keda_operator_role_arn" {
  description = "IAM role ARN for keda-operator (IRSA)."
  value       = module.keda.operator_role_arn
}

output "keda_chart_version" {
  description = "Installed KEDA Helm chart version."
  value       = module.keda.chart_version
}

output "keda_status" {
  description = "KEDA Helm release status."
  value       = module.keda.status
}

output "karpenter_controller_role_arn" {
  description = "IAM role ARN for the Karpenter controller (IRSA)."
  value       = module.karpenter.controller_role_arn
}

output "karpenter_chart_version" {
  description = "Installed Karpenter Helm chart version."
  value       = module.karpenter.chart_version
}

output "karpenter_status" {
  description = "Karpenter Helm release status."
  value       = module.karpenter.status
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue for Karpenter interruption handling."
  value       = module.karpenter.interruption_queue_name
}
