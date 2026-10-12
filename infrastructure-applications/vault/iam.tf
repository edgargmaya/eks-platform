data "aws_partition" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "AllowVaultServerIRSA"
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

resource "aws_iam_role" "server" {
  name               = "${var.cluster_name}-vault"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Auto-unseal only. Vault data is not stored in KMS; KMS wraps the root key.
data "aws_iam_policy_document" "unseal" {
  statement {
    sid    = "VaultAutoUnseal"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.unseal.arn]
  }
}

resource "aws_iam_role_policy" "unseal" {
  name   = "${var.cluster_name}-vault-unseal"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.unseal.json
}
