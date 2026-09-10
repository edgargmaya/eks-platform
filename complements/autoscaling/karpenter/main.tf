resource "helm_release" "this" {
  name       = "karpenter"
  namespace  = var.namespace
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = true

  values = [
    yamlencode({
      replicas = var.controller_replica_count

      # ClusterFirst is fine: Cilium + CoreDNS already run on the system NG.
      dnsPolicy = "ClusterFirst"

      serviceAccount = {
        create = true
        name   = var.service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.controller.arn
        }
      }

      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = var.cluster_endpoint
        interruptionQueue = aws_sqs_queue.interruption.name
        eksControlPlane   = true
        # Cilium ENI firstInterfaceIndex: 1 — do not count the primary ENI in max-pods.
        reservedENIs     = "1"
        enableZonalShift = false
      }

      controller = {
        resources = {
          requests = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.controller,
    aws_sqs_queue_policy.interruption,
    aws_cloudwatch_event_target.interruption,
  ]
}

# EC2NodeClass + NodePool after CRDs exist.
resource "helm_release" "nodeclass" {
  name             = "karpenter-nodeclass"
  namespace        = var.namespace
  chart            = "${path.module}/charts/nodeclass"
  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      clusterName            = var.cluster_name
      instanceProfile        = aws_iam_instance_profile.nodes.name
      clusterSecurityGroupId = var.cluster_security_group_id
      amiAlias               = var.ami_alias
      cpuLimit               = var.node_cpu_limit
    })
  ]

  depends_on = [helm_release.this]
}
