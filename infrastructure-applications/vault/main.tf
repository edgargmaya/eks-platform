locals {
  # Release name "vault" and chart name "vault" => Service vault-internal,
  # pods vault-0 .. vault-N. retry_join uses that headless DNS name.
  release_name = "vault"

  raft_retry_join = join("\n", [
    for i in range(var.replicas) : <<-JOIN
  retry_join {
    leader_api_addr = "http://${local.release_name}-${i}.${local.release_name}-internal:8200"
  }
JOIN
  ])

  # Listener TLS is off on purpose for this first install: the Service is
  # ClusterIP only. Raft data is encrypted by Vault; the root key is wrapped
  # by KMS. Do not publish this Service as a LoadBalancer until the listener
  # has certificates.
  raft_config = <<-EOT
ui = true
disable_mlock = true

listener "tcp" {
  tls_disable     = 1
  address         = "[::]:8200"
  cluster_address = "[::]:8201"
}

seal "awskms" {
  region     = "${var.aws_region}"
  kms_key_id = "${aws_kms_key.unseal.arn}"
}

storage "raft" {
  path = "/vault/data"
${local.raft_retry_join}
}

service_registration "kubernetes" {}
EOT
}

resource "helm_release" "runtime" {
  name             = "vault-runtime"
  namespace        = var.namespace
  chart            = "${path.module}/charts/runtime"
  wait             = true
  timeout          = var.helm_timeout_seconds
  atomic           = true
  cleanup_on_fail  = true
  create_namespace = true

  values = [
    yamlencode({
      nodePoolName     = var.node_pool_name
      nodeClassName    = var.node_class_name
      storageClassName = var.storage_class_name
      cpuLimit         = var.node_cpu_limit
    })
  ]
}

resource "helm_release" "this" {
  name       = local.release_name
  namespace  = var.namespace
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = var.chart_version

  # Sealed pods fail the chart readiness probe (vault status exits 2).
  # Waiting here would roll the release back before `operator init`.
  wait             = false
  timeout          = var.helm_timeout_seconds
  atomic           = false
  cleanup_on_fail  = true
  create_namespace = true

  values = [
    yamlencode({
      injector = {
        enabled = false
      }

      csi = {
        enabled = false
      }

      ui = {
        enabled     = true
        serviceType = "ClusterIP"
      }

      server = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            memory = "512Mi"
          }
        }

        nodeSelector = {
          "kubernetes.io/os"      = "linux"
          "karpenter.sh/nodepool" = var.node_pool_name
        }

        tolerations = [
          {
            key      = "dedicated"
            operator = "Equal"
            value    = "vault"
            effect   = "NoSchedule"
          }
        ]

        # One Vault pod per node. Zone spread prefers three AZs without
        # blocking the first pod while Karpenter is still launching.
        affinity = <<-EOT
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app.kubernetes.io/name: vault
          app.kubernetes.io/instance: ${local.release_name}
          component: server
      topologyKey: kubernetes.io/hostname
EOT

        topologySpreadConstraints = [
          {
            maxSkew           = 1
            topologyKey       = "topology.kubernetes.io/zone"
            whenUnsatisfiable = "ScheduleAnyway"
            labelSelector = {
              matchLabels = {
                "app.kubernetes.io/name"     = "vault"
                "app.kubernetes.io/instance" = local.release_name
                component                    = "server"
              }
            }
          }
        ]

        dataStorage = {
          enabled      = true
          size         = var.data_storage_size
          storageClass = var.storage_class_name
          persistentVolumeClaimRetentionPolicy = {
            whenDeleted = "Retain"
            whenScaled  = "Retain"
          }
        }

        serviceAccount = {
          create = true
          name   = var.service_account_name
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.server.arn
          }
        }

        standalone = {
          enabled = false
        }

        ha = {
          enabled  = true
          replicas = var.replicas
          raft = {
            enabled   = true
            setNodeId = true
            config    = local.raft_config
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.runtime,
    aws_iam_role_policy.unseal,
    aws_kms_alias.unseal,
  ]
}
