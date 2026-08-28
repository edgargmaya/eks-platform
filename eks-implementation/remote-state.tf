data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket         = var.tfstate_bucket_name
    key            = "bootstrap-infrastructure/terraform.tfstate"
    region         = var.aws_region
    encrypt        = true
    dynamodb_table = var.tfstate_lock_table_name
    kms_key_id     = "alias/${var.tfstate_kms_alias}"
  }
}

locals {
  vpc_id                   = data.terraform_remote_state.bootstrap.outputs.vpc_id
  vpc_cidr                 = data.terraform_remote_state.bootstrap.outputs.vpc_cidr
  public_subnet_ids        = data.terraform_remote_state.bootstrap.outputs.public_subnet_ids
  private_subnet_ids       = data.terraform_remote_state.bootstrap.outputs.private_subnet_ids
  control_plane_subnet_ids = data.terraform_remote_state.bootstrap.outputs.control_plane_subnet_ids
}
