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

module "cilium" {
  source = "../complements/networking/cilium"

  cluster_name           = module.cluster.cluster_name
  cluster_endpoint       = module.cluster.cluster_endpoint
  aws_region             = var.aws_region
  vpc_cidr               = local.vpc_cidr
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath
  chart_version          = var.cilium_chart_version
  enable_hubble_ui       = var.cilium_enable_hubble_ui

  depends_on = [module.nodegroup]
}

module "ebs" {
  source = "../complements/storage/ebs"

  cluster_name           = module.cluster.cluster_name
  cluster_version        = var.cluster_version
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath

  depends_on = [module.cilium]
}

module "lbc" {
  source = "../complements/loadbalancing/lbc"

  cluster_name           = module.cluster.cluster_name
  aws_region             = var.aws_region
  vpc_id                 = local.vpc_id
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath
  chart_version          = var.lbc_chart_version

  depends_on = [module.cilium]
}

module "metrics_server" {
  source = "../complements/autoscaling/metrics-server"

  chart_version = var.metrics_server_chart_version

  depends_on = [module.cilium]
}

module "keda" {
  source = "../complements/autoscaling/keda"

  cluster_name           = module.cluster.cluster_name
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath
  chart_version          = var.keda_chart_version

  depends_on = [module.cilium, module.lbc, module.metrics_server]
}

module "karpenter" {
  source = "../complements/autoscaling/karpenter"

  cluster_name              = module.cluster.cluster_name
  cluster_endpoint          = module.cluster.cluster_endpoint
  cluster_security_group_id = module.cluster.cluster_security_group_id
  oidc_provider_arn         = module.cluster.oidc_provider_arn
  oidc_provider_hostpath    = module.cluster.oidc_provider_hostpath
  node_role_name            = module.iam.node_role_name
  node_role_arn             = module.iam.node_role_arn
  chart_version             = var.karpenter_chart_version

  depends_on = [module.cilium, module.lbc, module.keda]
}

# Preserve state after merging modules/cilium-iam into this complement.
moved {
  from = module.cilium_iam.aws_iam_role.operator
  to   = module.cilium.aws_iam_role.operator
}

moved {
  from = module.cilium_iam.aws_iam_role_policy.operator_eni
  to   = module.cilium.aws_iam_role_policy.operator_eni
}
