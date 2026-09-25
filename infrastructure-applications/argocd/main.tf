locals {
  # Chart default is kubernetes.io/os=linux. Merge so an extra selector
  # does not drop the OS constraint.
  node_selector = merge(
    { "kubernetes.io/os" = "linux" },
    var.node_selector,
  )

  ingress_annotations = {
    "alb.ingress.kubernetes.io/scheme"           = var.ingress_scheme
    "alb.ingress.kubernetes.io/target-type"      = "ip"
    "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
    "alb.ingress.kubernetes.io/listen-ports"     = jsonencode([{ HTTP = 80 }])
    "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
  }

  helm_values = merge(
    {
      global = merge(
        {
          nodeSelector = local.node_selector
        },
        var.ingress_enabled ? { domain = var.ingress_hostname } : {},
      )

      crds = {
        install = true
        keep    = true
      }

      dex = {
        enabled = var.dex_enabled
      }

      notifications = {
        enabled = var.notifications_enabled
      }

      # Single Redis. HA Redis is a second chart and several extra pods.
      "redis-ha" = {
        enabled = false
      }

      controller = {
        replicas = var.controller_replicas
      }

      repoServer = {
        replicas = var.repo_server_replicas
      }

      applicationSet = {
        replicas = var.application_set_replicas
      }

      server = merge(
        {
          replicas = var.server_replicas
        },
        var.ingress_enabled ? {
          ingress = {
            enabled          = true
            controller       = "generic"
            ingressClassName = var.ingress_class_name
            hostname         = var.ingress_hostname
            path             = "/"
            pathType         = "Prefix"
            annotations      = local.ingress_annotations
          }
        } : {},
      )
    },
    # TLS stays on for kubectl port-forward. The ALB speaks HTTP to the
    # pod, so the server must disable its own TLS when Ingress is on.
    var.ingress_enabled ? {
      configs = {
        params = {
          "server.insecure" = "true"
        }
      }
    } : {},
  )
}

resource "helm_release" "this" {
  name       = "argocd"
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = true

  values = [yamlencode(local.helm_values)]
}
