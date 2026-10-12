variable "chart_version" {
  description = "External Secrets Operator Helm chart version from https://charts.external-secrets.io (2.11.0 tracks app v2.11.0)."
  type        = string
  default     = "2.11.0"
}

variable "namespace" {
  description = "Namespace where External Secrets Operator is installed."
  type        = string
  default     = "external-secrets"
}

variable "replica_count" {
  description = "Controller replicas. One is enough until the operator itself needs HA."
  type        = number
  default     = 1
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout, including CRDs and the webhook."
  type        = number
  default     = 600
}
