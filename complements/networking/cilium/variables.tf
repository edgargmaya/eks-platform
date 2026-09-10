variable "cluster_name" {
  description = "EKS cluster name. Used on the operator IAM role and as Cilium cluster.name."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint URL. Used as k8sServiceHost when kube-proxy is replaced."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the operator SDK (EC2 ENI API)."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR used as ipv4NativeRoutingCIDR for ENI/native routing."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the cluster module (IRSA trust)."
  type        = string
}

variable "oidc_provider_hostpath" {
  description = "OIDC issuer without https://, used in the IRSA trust condition."
  type        = string
}

variable "chart_version" {
  description = "Cilium Helm chart version."
  type        = string
  default     = "1.20.1"
}

variable "namespace" {
  description = "Namespace where Cilium is installed (must match the IRSA service account)."
  type        = string
  default     = "kube-system"
}

variable "operator_service_account_name" {
  description = "Service account name created by the Cilium chart for the operator. Must match the IRSA trust sub."
  type        = string
  default     = "cilium-operator"
}

variable "masquerade_interface" {
  description = "Primary node interface used for egress masquerade. AL2023 EKS AMIs expose ens5 (not eth0)."
  type        = string
  default     = "ens5"
}

variable "enable_hubble" {
  description = "Enable Hubble flow visibility."
  type        = bool
  default     = true
}

variable "enable_hubble_ui" {
  description = "Deploy Hubble UI (ClusterIP; use kubectl port-forward)."
  type        = bool
  default     = true
}

variable "enable_prefix_delegation" {
  description = "Allocate /28 prefixes on ENIs for higher pod density (Nitro instances)."
  type        = bool
  default     = true
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout for the Cilium release."
  type        = number
  default     = 900
}

variable "disable_legacy_cni_timeout_seconds" {
  description = "Helm wait timeout for the in-cluster aws-node/kube-proxy patch Job."
  type        = number
  default     = 300
}

variable "kubectl_image" {
  description = "kubectl image for the disable-legacy-cni Job. Must exist; Bitnami public.ecr.aws/bitnami/kubectl:1.35.0 does not."
  type        = string
  default     = "registry.k8s.io/kubectl:v1.35.0"
}
