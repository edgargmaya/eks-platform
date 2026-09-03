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
  value       = module.cilium_iam.operator_role_arn
}

output "cilium_chart_version" {
  description = "Installed Cilium Helm chart version."
  value       = module.cilium.chart_version
}

output "cilium_status" {
  description = "Cilium Helm release status."
  value       = module.cilium.status
}
