resource "helm_release" "this" {
  name       = "metrics-server"
  namespace  = var.namespace
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = false

  values = [
    yamlencode({
      replicas = var.replica_count

      # Cilium ENI + native routing: pods are VPC IPs. The API server can
      # reach the metrics-server Service without hostNetwork.
      hostNetwork = {
        enabled = false
      }

      args = var.kubelet_insecure_tls ? ["--kubelet-insecure-tls"] : []
    })
  ]
}
