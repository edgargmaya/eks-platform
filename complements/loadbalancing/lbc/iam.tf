data "aws_partition" "current" {}

# IRSA trust: this cluster's OIDC provider, only aws-load-balancer-controller.
# Cluster-level OIDC registration lives in modules/cluster/irsa.tf.
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "AllowAwsLoadBalancerControllerIRSA"
    effect = "Allow"
    actions = [
      "sts:AssumeRoleWithWebIdentity",
      "sts:TagSession",
    ]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_hostpath}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_hostpath}:aud"
      values   = ["sts.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Official controller policy (not an AWS-managed policy). Vendored from
# kubernetes-sigs/aws-load-balancer-controller v3.5.0
# docs/install/iam_policy.json so apply does not fetch GitHub.
resource "aws_iam_policy" "controller" {
  name   = "${var.cluster_name}-aws-load-balancer-controller"
  policy = file("${path.module}/iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}
