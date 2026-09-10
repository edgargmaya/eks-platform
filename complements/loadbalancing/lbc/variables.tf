variable "cluster_name" {
  description = "EKS cluster name. Passed to the controller as clusterName and used on the IAM role."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the controller SDK (ELB/EC2 APIs)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID. Set explicitly so the controller does not depend on IMDS for VPC discovery."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the cluster module (IRSA trust principal)."
  type        = string
}

variable "oidc_provider_hostpath" {
  description = "OIDC issuer without https://, used in the IRSA trust condition."
  type        = string
}

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version from https://aws.github.io/eks-charts (appVersion matches, for example 3.5.0 → v3.5.0)."
  type        = string
  default     = "3.5.0"
}

variable "namespace" {
  description = "Namespace of the controller ServiceAccount (kube-system for the official chart)."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Service account the Helm chart creates. Must match the IRSA trust sub."
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "replica_count" {
  description = "Controller replicas. The webhook failurePolicy is Fail; keep at least 2 when the node group has two or more nodes."
  type        = number
  default     = 2
}

variable "default_target_type" {
  description = "Default ALB/NLB target type. ip is required for Cilium ENI (real VPC pod IPs)."
  type        = string
  default     = "ip"

  validation {
    condition     = contains(["ip", "instance"], var.default_target_type)
    error_message = "default_target_type must be ip or instance."
  }
}

variable "ingress_class" {
  description = "IngressClass name the controller watches (chart also creates this IngressClass)."
  type        = string
  default     = "alb"
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout for the controller release (includes webhook readiness)."
  type        = number
  default     = 600
}
