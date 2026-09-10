resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  namespace  = var.namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id

      # Cilium ENI + native routing (bpf.masquerade=false): pods are VPC IPs.
      # instance mode would hairpin through NodePort instead of targeting pods.
      defaultTargetType = var.default_target_type

      replicaCount = var.replica_count

      serviceAccount = {
        create = true
        name   = var.service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.controller.arn
        }
      }

      createIngressClassResource = true
      ingressClass               = var.ingress_class
    })
  ]

  depends_on = [aws_iam_role_policy_attachment.controller]
}
