aws_region      = "us-east-1"
cluster_name    = "alesia"
cluster_version = "1.35"

# Must match bootstrap-infrastructure/terraform.tfvars and backend.tf
tfstate_bucket_name     = "eks-platform-alesia"
tfstate_lock_table_name = "eks-platform-alesia-tf-locks"
tfstate_kms_alias       = "eks-platform-alesia-tfstate"

# Lab default. Replace with office / VPN CIDRs before production.
endpoint_public_access_cidrs = ["0.0.0.0/0"]

node_instance_types = ["t3.medium"]
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 6

cilium_chart_version    = "1.20.1"
cilium_enable_hubble_ui = true
