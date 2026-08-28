# Generated to match bootstrap-infrastructure terraform.tfvars. Keep these values in sync.
terraform {
  backend "s3" {
    bucket         = "eks-platform-alesia"
    key            = "eks-implementation/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "eks-platform-alesia-tf-locks"
    kms_key_id     = "alias/eks-platform-alesia-tfstate"
  }
}
