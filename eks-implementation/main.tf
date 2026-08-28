module "iam" {
  source = "../modules/iam"

  cluster_name = var.cluster_name
}

module "cluster" {
  source = "../modules/cluster"

  cluster_name     = var.cluster_name
  cluster_version  = var.cluster_version
  cluster_role_arn = module.iam.cluster_role_arn

  subnet_ids         = values(local.control_plane_subnet_ids)
  public_subnet_ids  = local.public_subnet_ids
  private_subnet_ids = local.private_subnet_ids

  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  depends_on = [module.iam]
}

module "nodegroup" {
  source = "../modules/nodegroup"

  cluster_name                       = module.cluster.cluster_name
  cluster_version                    = var.cluster_version
  cluster_endpoint                   = module.cluster.cluster_endpoint
  cluster_certificate_authority_data = module.cluster.cluster_certificate_authority_data
  service_ipv4_cidr                  = module.cluster.service_ipv4_cidr
  node_role_arn                      = module.iam.node_role_arn
  subnet_ids                         = values(local.private_subnet_ids)
  instance_types                     = var.node_instance_types
  desired_size                       = var.node_desired_size
  min_size                           = var.node_min_size
  max_size                           = var.node_max_size
}
