variable "cluster_name" {
  description = "EKS cluster name; used as a prefix on IAM role names."
  type        = string
}

variable "enable_ssm_managed_instance_core" {
  description = "Attach AmazonSSMManagedInstanceCore to the node role (Session Manager, not FullAccess)."
  type        = bool
  default     = true
}
