output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_id" {
  description = "EKS cluster id (same as name)."
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_version" {
  description = "Kubernetes version reported by EKS."
  value       = aws_eks_cluster.this.version
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA (for kubeconfig and nodeadm)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Cluster security group created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "service_ipv4_cidr" {
  description = "Kubernetes service IPv4 CIDR."
  value       = aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_hostpath" {
  description = "OIDC issuer without https://, for IAM trust conditions."
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "kms_key_arn" {
  description = "CMK used for secrets encryption and control-plane logs."
  value       = aws_kms_key.eks.arn
}
