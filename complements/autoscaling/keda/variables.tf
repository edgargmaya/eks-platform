variable "cluster_name" {
  description = "EKS cluster name. Used on the IAM role and as KEDA clusterName."
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
  description = "KEDA Helm chart version from https://kedacore.github.io/charts (appVersion matches, for example 2.20.2)."
  type        = string
  default     = "2.20.2"
}

variable "namespace" {
  description = "Namespace where KEDA is installed (must match the IRSA service account)."
  type        = string
  default     = "keda"
}

variable "operator_service_account_name" {
  description = "Service account the chart creates for the operator. Must match the IRSA trust sub."
  type        = string
  default     = "keda-operator"
}

variable "operator_replica_count" {
  description = "KEDA operator replicas. Only one is leader; extras only shorten failover."
  type        = number
  default     = 1
}

variable "metrics_server_replica_count" {
  description = "KEDA metrics API server replicas. Only one serves traffic."
  type        = number
  default     = 1
}

variable "webhook_replica_count" {
  description = "Admission webhook replicas. failurePolicy is Ignore, so 1 is enough on a two-node lab."
  type        = number
  default     = 1
}

variable "operator_iam_policy_json" {
  description = "Optional IAM policy JSON for AWS scalers (SQS, CloudWatch, …) assumed via identityOwner: keda. Null means no AWS API permissions yet."
  type        = string
  default     = null
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout for the KEDA release (includes webhook readiness)."
  type        = number
  default     = 600
}
