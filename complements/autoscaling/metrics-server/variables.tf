variable "chart_version" {
  description = "metrics-server Helm chart version from https://kubernetes-sigs.github.io/metrics-server (for example 3.14.0 → app 0.9.0)."
  type        = string
  default     = "3.14.0"
}

variable "namespace" {
  description = "Namespace where metrics-server is installed. kube-system matches the upstream chart."
  type        = string
  default     = "kube-system"
}

variable "replica_count" {
  description = "metrics-server replicas. One is enough on a two-node lab; the Deployment is not highly available by default."
  type        = number
  default     = 1
}

variable "kubelet_insecure_tls" {
  description = "Pass --kubelet-insecure-tls. Required on EKS: kubelet serving certs are not signed by a CA metrics-server trusts."
  type        = bool
  default     = true
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout for the metrics-server release (includes APIService readiness)."
  type        = number
  default     = 300
}
