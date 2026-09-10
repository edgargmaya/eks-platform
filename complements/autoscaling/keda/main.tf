resource "helm_release" "this" {
  name       = "keda"
  namespace  = var.namespace
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = true

  values = [
    yamlencode({
      clusterName = var.cluster_name

      operator = {
        replicaCount = var.operator_replica_count
      }

      metricsServer = {
        replicaCount = var.metrics_server_replica_count
      }

      webhooks = {
        replicaCount = var.webhook_replica_count
        # Cilium ENI gives pods real VPC IPs; hostNetwork is not required.
        useHostNetwork = false
      }

      serviceAccount = {
        operator = {
          create = true
          name   = var.operator_service_account_name
        }
      }

      # Official chart IRSA knobs: annotates keda-operator only.
      podIdentity = {
        aws = {
          irsa = {
            enabled              = true
            roleArn              = aws_iam_role.operator.arn
            stsRegionalEndpoints = "true"
          }
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role.operator,
    aws_iam_role_policy.aws_scalers,
  ]
}
