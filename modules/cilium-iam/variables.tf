variable "cluster_name" {
  description = "EKS cluster name; used as a prefix on the operator IAM role."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN from the cluster module."
  type        = string
}

variable "oidc_provider_hostpath" {
  description = "OIDC issuer without https://, used in the IRSA trust condition."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the cilium-operator service account."
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Service account name created by the Cilium Helm chart for the operator."
  type        = string
  default     = "cilium-operator"
}
