variable "cluster_name" {
  description = "EKS cluster name. Used on the IAM role and the KMS alias."
  type        = string
}

variable "aws_region" {
  description = "Region of the KMS key Vault uses for auto-unseal."
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
  description = "HashiCorp Vault Helm chart version (hashicorp/vault). 0.34.1 tracks Vault 2.0.4."
  type        = string
  default     = "0.34.1"
}

variable "namespace" {
  description = "Namespace where Vault is installed."
  type        = string
  default     = "vault"
}

variable "service_account_name" {
  description = "Service account Vault runs as. Must match the IRSA trust sub."
  type        = string
  default     = "vault"
}

variable "replicas" {
  description = "Raft voters. 3 survives one loss. 5 survives two. Two is not a quorum."
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5], var.replicas)
    error_message = "replicas must be 3 or 5 so Raft keeps a majority after a failure."
  }
}

variable "storage_class_name" {
  description = "StorageClass for Raft PVCs. Created by this module with reclaim Retain."
  type        = string
  default     = "vault-gp3"
}

variable "data_storage_size" {
  description = "Size of each Raft PVC."
  type        = string
  default     = "10Gi"
}

variable "node_pool_name" {
  description = "Karpenter NodePool that may run Vault. Pods select and taint this pool."
  type        = string
  default     = "vault"
}

variable "node_class_name" {
  description = "Existing EC2NodeClass the Vault NodePool references. The Karpenter complement creates default."
  type        = string
  default     = "default"
}

variable "node_cpu_limit" {
  description = "Total vCPU Karpenter may launch for the Vault NodePool. Three 2-vCPU nodes need 6."
  type        = number
  default     = 8
}

variable "helm_timeout_seconds" {
  description = "Helm timeout for the runtime chart and the Vault release. Vault itself is not waited on: pods stay unready until operator init."
  type        = number
  default     = 600
}
