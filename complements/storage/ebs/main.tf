data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # IRSA: EKS annotates ebs-csi-controller-sa with this role. Do not set
  # pod_identity_association — that is the Pod Identity path.
  service_account_role_arn = aws_iam_role.controller.arn

  # Own StorageClass is created below (encrypted gp3). The add-on's
  # defaultStorageClass would be a second default without encryption knobs.
  configuration_values = jsonencode({
    defaultStorageClass = {
      enabled = false
    }
  })

  depends_on = [aws_iam_role_policy_attachment.controller]
}

resource "helm_release" "gp3" {
  name             = "ebs-gp3-storageclass"
  namespace        = var.namespace
  chart            = "${path.module}/charts/gp3-storageclass"
  wait             = true
  timeout          = 120
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      name      = var.storage_class_name
      isDefault = var.make_default_storage_class
      encrypted = true
      kmsKeyId  = var.kms_key_arn
    })
  ]

  depends_on = [aws_eks_addon.ebs_csi]
}
