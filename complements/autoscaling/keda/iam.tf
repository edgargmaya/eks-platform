data "aws_partition" "current" {}

# IRSA trust: this cluster's OIDC provider, only keda-operator.
# Cluster-level OIDC registration lives in modules/cluster/irsa.tf.
# Metrics API and admission webhook SAs do not call AWS APIs.
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "AllowKedaOperatorIRSA"
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
      values   = ["system:serviceaccount:${var.namespace}:${var.operator_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_hostpath}:aud"
      values   = ["sts.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "operator" {
  name               = "${var.cluster_name}-keda-operator"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Optional AWS scaler permissions (SQS, CloudWatch, …). Core KEDA (cron,
# kubernetes-workload, prometheus) does not need IAM. Attach JSON here
# when a trigger uses identityOwner: keda.
resource "aws_iam_role_policy" "aws_scalers" {
  count = var.operator_iam_policy_json == null ? 0 : 1

  name   = "${var.cluster_name}-keda-aws-scalers"
  role   = aws_iam_role.operator.id
  policy = var.operator_iam_policy_json
}
