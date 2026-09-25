variable "chart_version" {
  description = "argo-cd Helm chart version from https://argoproj.github.io/argo-helm (for example 10.9.2 tracks Argo CD 3.5.x)."
  type        = string
  default     = "10.9.2"
}

variable "namespace" {
  description = "Namespace where Argo CD is installed."
  type        = string
  default     = "argocd"
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout. Includes image pull and, when node_selector targets an empty Karpenter pool, node join."
  type        = number
  default     = 900
}

variable "server_replicas" {
  description = "argocd-server replicas. One is enough until the API/UI needs HA."
  type        = number
  default     = 1
}

variable "controller_replicas" {
  description = "Application controller replicas. More than one shards clusters; keep 1 on a single cluster."
  type        = number
  default     = 1
}

variable "repo_server_replicas" {
  description = "Repo server replicas."
  type        = number
  default     = 1
}

variable "application_set_replicas" {
  description = "ApplicationSet controller replicas."
  type        = number
  default     = 1
}

variable "dex_enabled" {
  description = "Install Dex. Leave false until an SSO connector is configured; an idle Dex pod only consumes an IP."
  type        = bool
  default     = false
}

variable "notifications_enabled" {
  description = "Install the notifications controller."
  type        = bool
  default     = true
}

variable "node_selector" {
  description = "Extra node selector merged onto kubernetes.io/os=linux for every Argo CD pod. Example: karpenter.sh/nodepool=default."
  type        = map(string)
  default     = {}
}

variable "ingress_enabled" {
  description = "Expose the UI with an Ingress. Requires an IngressClass (this platform uses alb) and ingress_hostname."
  type        = bool
  default     = false
}

variable "ingress_class_name" {
  description = "IngressClass for the UI. alb matches the AWS Load Balancer Controller complement."
  type        = string
  default     = "alb"
}

variable "ingress_scheme" {
  description = "ALB scheme when ingress_enabled is true: internet-facing or internal."
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.ingress_scheme)
    error_message = "ingress_scheme must be internet-facing or internal."
  }
}

variable "ingress_hostname" {
  description = "UI hostname. Required when ingress_enabled is true. The chart always sets a host rule; an empty host would fall back to argocd.example.com."
  type        = string
  default     = ""

  validation {
    condition     = !var.ingress_enabled || length(var.ingress_hostname) > 0
    error_message = "ingress_hostname is required when ingress_enabled is true."
  }
}
