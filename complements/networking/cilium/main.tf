locals {
  k8s_service_host = replace(replace(var.cluster_endpoint, "https://", ""), "http://", "")
}

# Park aws-node and kube-proxy from inside the cluster. Helm talks to the
# API with the same exec authenticator as cilium; the Job uses a real
# kubectl image (registry.k8s.io) on hostNetwork so it does not need the
# workstation kubeconfig or a working pod CNI.
resource "helm_release" "disable_legacy_cni" {
  name             = "disable-legacy-cni"
  namespace        = var.namespace
  chart            = "${path.module}/charts/disable-legacy-cni"
  wait             = true
  timeout          = var.disable_legacy_cni_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      kubectlImage  = var.kubectl_image
      apiServerHost = local.k8s_service_host
      apiServerPort = "443"
    })
  ]
}

resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = var.namespace
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = false
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    templatefile("${path.module}/values.yaml.tftpl", {
      cluster_name                  = var.cluster_name
      vpc_cidr                      = var.vpc_cidr
      masquerade_interface          = var.masquerade_interface
      enable_prefix_delegation      = var.enable_prefix_delegation
      k8s_service_host              = local.k8s_service_host
      operator_service_account_name = var.operator_service_account_name
      operator_role_arn             = aws_iam_role.operator.arn
      enable_hubble                 = var.enable_hubble
      enable_hubble_ui              = var.enable_hubble_ui
      aws_region                    = var.aws_region
    })
  ]

  depends_on = [
    helm_release.disable_legacy_cni,
    aws_iam_role_policy.operator_eni,
  ]
}
