resource "helm_release" "this" {
  name       = "external-secrets"
  namespace  = var.namespace
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = true

  values = [
    yamlencode({
      installCRDs  = true
      replicaCount = var.replica_count

      webhook = {
        replicaCount = 1
      }

      certController = {
        replicaCount = 1
      }
    })
  ]
}
