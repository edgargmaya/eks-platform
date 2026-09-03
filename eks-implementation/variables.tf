variable "aws_region" {
  description = "AWS region. Must match bootstrap-infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name. Also used as a prefix on IAM roles, KMS aliases, and node groups."
  type        = string
  default     = "alesia"
}

variable "cluster_version" {
  description = "Kubernetes version for the control plane and for the SSM AMI lookup (minor version, for example 1.35)."
  type        = string
  default     = "1.35"
}

variable "endpoint_public_access" {
  description = "Enable the public EKS API endpoint."
  type        = bool
  default     = true
}

variable "endpoint_private_access" {
  description = "Enable the private EKS API endpoint."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Restrict this in production; 0.0.0.0/0 is a lab default."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the default managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "tfstate_bucket_name" {
  description = "S3 bucket that holds platform state. Must match bootstrap-infrastructure."
  type        = string
}

variable "tfstate_lock_table_name" {
  description = "DynamoDB lock table. Must match bootstrap-infrastructure."
  type        = string
}

variable "tfstate_kms_alias" {
  description = "KMS alias (without alias/) used to encrypt state. Must match bootstrap-infrastructure."
  type        = string
}

variable "cilium_chart_version" {
  description = "Cilium Helm chart version."
  type        = string
  default     = "1.20.1"
}

variable "cilium_enable_hubble_ui" {
  description = "Deploy Hubble UI as ClusterIP (kubectl port-forward)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags merged into the provider default_tags."
  type        = map(string)
  default = {
    "infra:product-stream" = "cloud-engineering"
    "infra:team"           = "cloud-engineering"
    "infra:supported-by"   = "cloud-engineering"
    Project                = "eks-platform-alesia"
    ManagedBy              = "terraform"
  }
}
