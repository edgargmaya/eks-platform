variable "cluster_name" {
  description = "EKS cluster name. Used on IAM roles, the interruption queue, and Karpenter settings.clusterName."
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint. Passed to Karpenter settings.clusterEndpoint."
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS cluster security group. Karpenter nodes join this SG (same path as managed nodes talking to the API)."
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

variable "node_role_name" {
  description = "Existing node IAM role name (managed node group). Karpenter instance profile reuses it so EKS Access Entries already allow EC2_LINUX join."
  type        = string
}

variable "node_role_arn" {
  description = "ARN of node_role_name. Controller iam:PassRole is scoped to this role."
  type        = string
}

variable "chart_version" {
  description = "Karpenter Helm chart version from oci://public.ecr.aws/karpenter (appVersion matches, for example 1.14.1)."
  type        = string
  default     = "1.14.1"
}

variable "namespace" {
  description = "Namespace where Karpenter is installed (must match the IRSA service account)."
  type        = string
  default     = "karpenter"
}

variable "service_account_name" {
  description = "Service account the chart creates. Must match the IRSA trust sub."
  type        = string
  default     = "karpenter"
}

variable "controller_replica_count" {
  description = "Karpenter controller replicas. 1 fits a two-node system node group; raise when the system pool has two AZs with spare CPU."
  type        = number
  default     = 1
}

variable "ami_alias" {
  description = "EC2NodeClass amiSelectorTerms alias (AL2023 EKS-optimized). Pin a v-number in production."
  type        = string
  default     = "al2023@latest"
}

variable "node_cpu_limit" {
  description = "NodePool CPU limit (cores). Caps how much Karpenter can launch."
  type        = number
  default     = 32
}

variable "helm_timeout_seconds" {
  description = "Helm wait timeout for the controller and NodePool releases."
  type        = number
  default     = 600
}
