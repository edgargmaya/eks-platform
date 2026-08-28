variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version (for example 1.35)."
  type        = string
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane (from the iam module)."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for EKS control-plane ENIs. Use the dedicated /28 subnets from bootstrap."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS requires at least two subnets in different AZs for the control plane."
  }
}

variable "public_subnet_ids" {
  description = "Map of AZ => public subnet ID. Tagged kubernetes.io/cluster/<name>=shared for public LBs."
  type        = map(string)
}

variable "private_subnet_ids" {
  description = "Map of AZ => private subnet ID. Tagged kubernetes.io/cluster/<name>=shared for internal LBs."
  type        = map(string)
}

variable "service_ipv4_cidr" {
  description = "Kubernetes service CIDR. Must not overlap the VPC CIDR (10.0.0.0/16)."
  type        = string
  default     = "172.20.0.0/16"
}

variable "endpoint_private_access" {
  description = "Enable the private EKS API endpoint."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable the public EKS API endpoint."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Restrict this in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control-plane log types sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "CloudWatch log group retention for /aws/eks/<cluster>/cluster."
  type        = number
  default     = 30
}

variable "authentication_mode" {
  description = "EKS access authentication mode. API is the current Access Entry model; CONFIG_MAP is legacy aws-auth."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API, API_AND_CONFIG_MAP, or CONFIG_MAP."
  }
}
