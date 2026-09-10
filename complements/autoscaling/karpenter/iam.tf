data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.region
  account   = data.aws_caller_identity.current.account_id
}

# IRSA trust: this cluster's OIDC provider, only karpenter/karpenter.
# Cluster-level OIDC registration lives in modules/cluster/irsa.tf.
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "AllowKarpenterControllerIRSA"
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
  name               = "${var.cluster_name}-karpenter"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# --- Node lifecycle (RunInstances / CreateFleet / Terminate, tagged to this cluster) ---

data "aws_iam_policy_document" "node_lifecycle" {
  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}::image/*",
      "arn:${local.partition}:ec2:${local.region}::snapshot/*",
      "arn:${local.partition}:ec2:${local.region}:*:security-group/*",
      "arn:${local.partition}:ec2:${local.region}:*:subnet/*",
      "arn:${local.partition}:ec2:${local.region}:*:capacity-reservation/*",
      "arn:${local.partition}:ec2:${local.region}:*:placement-group/*",
    ]
  }

  statement {
    sid    = "AllowScopedEC2LaunchTemplateAccessActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid     = "AllowScopedResourceCreationTagging"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:fleet/*",
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:volume/*",
      "arn:${local.partition}:ec2:${local.region}:*:network-interface/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
      "arn:${local.partition}:ec2:${local.region}:*:spot-instances-request/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedResourceTagging"
    effect    = "Allow"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.partition}:ec2:${local.region}:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["eks:eks-cluster-name", "karpenter.sh/nodeclaim", "Name"]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
    ]
    resources = [
      "arn:${local.partition}:ec2:${local.region}:*:instance/*",
      "arn:${local.partition}:ec2:${local.region}:*:launch-template/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }
}

# --- PassRole for the node instance profile + optional Karpenter-managed profiles ---

data "aws_iam_policy_document" "iam_integration" {
  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [var.node_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileCreationActions"
    effect    = "Allow"
    actions   = ["iam:CreateInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowScopedInstanceProfileTagActions"
    effect    = "Allow"
    actions   = ["iam:TagInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks:eks-cluster-name"
      values   = [var.cluster_name]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedInstanceProfileActions"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
    ]
    resources = ["arn:${local.partition}:iam::${local.account}:instance-profile/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"
      values   = [local.region]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
      values   = ["*"]
    }
  }
}

data "aws_iam_policy_document" "eks_integration" {
  statement {
    sid       = "AllowAPIServerEndpointDiscovery"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account}:cluster/${var.cluster_name}"]
  }
}

data "aws_iam_policy_document" "interruption" {
  statement {
    sid    = "AllowInterruptionQueueActions"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
    resources = [aws_sqs_queue.interruption.arn]
  }
}

data "aws_iam_policy_document" "resource_discovery" {
  statement {
    sid    = "AllowRegionalReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "AllowSSMReadActions"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}::parameter/aws/service/*"]
  }

  statement {
    sid       = "AllowPricingReadActions"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowUnscopedInstanceProfileListAction"
    effect    = "Allow"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInstanceProfileReadActions"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = ["arn:${local.partition}:iam::${local.account}:instance-profile/*"]
  }
}

locals {
  controller_policies = {
    lifecycle    = data.aws_iam_policy_document.node_lifecycle.json
    iam          = data.aws_iam_policy_document.iam_integration.json
    eks          = data.aws_iam_policy_document.eks_integration.json
    interruption = data.aws_iam_policy_document.interruption.json
    discovery    = data.aws_iam_policy_document.resource_discovery.json
  }
}

resource "aws_iam_policy" "controller" {
  for_each = local.controller_policies

  name   = "${var.cluster_name}-karpenter-${each.key}"
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "controller" {
  for_each = aws_iam_policy.controller

  role       = aws_iam_role.controller.name
  policy_arn = each.value.arn
}

# Reuse the managed node group role. EKS already created an EC2_LINUX
# access entry for it, so Karpenter instances can join without aws-auth.
resource "aws_iam_instance_profile" "nodes" {
  name = "${var.cluster_name}-karpenter-nodes"
  role = var.node_role_name
}
