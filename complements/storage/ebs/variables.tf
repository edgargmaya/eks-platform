variable "cluster_name" {
  description = "EKS cluster name the managed add-on attaches to."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version (minor, for example 1.35) used to resolve a compatible add-on version."
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

variable "controller_service_account_name" {
  description = "Service account the EBS CSI controller uses. The managed add-on always creates ebs-csi-controller-sa."
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "namespace" {
  description = "Namespace of the EBS CSI controller service account (kube-system for the EKS add-on)."
  type        = string
  default     = "kube-system"
}

variable "kms_key_arn" {
  description = "Optional CMK ARN for volume encryption. Null uses the AWS-managed aws/ebs key (encrypted=true on the StorageClass)."
  type        = string
  default     = null
}

variable "storage_class_name" {
  description = "Name of the default gp3 StorageClass this module creates."
  type        = string
  default     = "gp3"
}

variable "make_default_storage_class" {
  description = "Annotate the gp3 StorageClass as the cluster default."
  type        = bool
  default     = true
}
