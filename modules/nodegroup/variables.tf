variable "cluster_name" {
  description = "EKS cluster name the node group joins."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version used to look up the EKS-optimized AMI in SSM Parameter Store (for example 1.35)."
  type        = string
}

variable "cluster_endpoint" {
  description = "Cluster API endpoint, passed to nodeadm."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA, passed to nodeadm."
  type        = string
  sensitive   = true
}

variable "service_ipv4_cidr" {
  description = "Kubernetes service CIDR, passed to nodeadm."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for worker nodes (from the iam module)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for worker nodes. Use the /19 node subnets from bootstrap, not the /28 control-plane subnets."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Place worker nodes in at least two AZs."
  }
}

variable "node_group_name" {
  description = "Short name appended to the cluster name for this node group."
  type        = string
  default     = "workers"
}

variable "instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "desired_size" {
  description = "Desired node count at creation. Later changes are ignored so Cluster Autoscaler can scale without Terraform reverting them."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum node count."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum node count."
  type        = number
  default     = 6
}

variable "disk_size_gb" {
  description = "Root volume size in GiB (gp3)."
  type        = number
  default     = 80
}

variable "ami_id" {
  description = "Optional AMI override. When null, the latest recommended EKS-optimized AMI for cluster_version is read from SSM."
  type        = string
  default     = null
}

variable "ami_architecture" {
  description = "SSM AMI architecture: x86_64 or arm64. Must match instance_types."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.ami_architecture)
    error_message = "ami_architecture must be x86_64 or arm64."
  }
}

variable "ami_variant" {
  description = "SSM AMI variant under amazon-linux-2023/<arch>/: standard, nvidia, or neuron."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "nvidia", "neuron"], var.ami_variant)
    error_message = "ami_variant must be standard, nvidia, or neuron."
  }
}

variable "labels" {
  description = "Kubernetes labels applied to nodes in this group."
  type        = map(string)
  default     = {}
}
