# Cluster-level IRSA enablement (not per-addon IAM).
#
# EKS always exposes an OIDC issuer URL on the control plane. IAM must
# trust that issuer as an OpenID Connect provider before any workload can
# call sts:AssumeRoleWithWebIdentity. That registration is a property of
# *this* cluster, 1:1 with aws_eks_cluster.this, so it lives here — not in
# modules/iam and not in a complement module.
#
# Complements only consume oidc_provider_arn / oidc_provider_hostpath and
# declare their own ServiceAccount, IAM role, permission policy, and
# trust policy (sub = system:serviceaccount:<ns>:<sa>).
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.${data.aws_partition.current.dns_suffix}"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.cluster_name}-irsa"
  }
}
