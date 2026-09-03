provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# Tokens from aws_eks_cluster_auth expire in ~15 minutes. exec refreshes them
# for the Helm wait on Cilium (can exceed that window).
provider "helm" {
  kubernetes = {
    host                   = module.cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.cluster.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        var.cluster_name,
        "--region",
        var.aws_region,
      ]
    }
  }
}
