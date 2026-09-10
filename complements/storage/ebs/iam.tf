data "aws_partition" "current" {}

# IRSA trust: this cluster's OIDC provider, only ebs-csi-controller-sa.
# Cluster-level OIDC registration lives in modules/cluster/irsa.tf.
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "AllowEbsCsiControllerIRSA"
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
      values   = ["system:serviceaccount:${var.namespace}:${var.controller_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_hostpath}:aud"
      values   = ["sts.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = "${var.cluster_name}-ebs-csi-controller"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# AWS-maintained policy for the EBS CSI controller (EC2 volume lifecycle).
# V2 is not under service-role/; that path 404s. ARN is /AmazonEBSCSIDriverPolicyV2.
resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

data "aws_iam_policy_document" "kms" {
  count = var.kms_key_arn == null ? 0 : 1

  statement {
    sid    = "EbsCsiKmsGrants"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = [var.kms_key_arn]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  statement {
    sid    = "EbsCsiKmsUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "controller_kms" {
  count = var.kms_key_arn == null ? 0 : 1

  name   = "${var.cluster_name}-ebs-csi-kms"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.kms[0].json
}
