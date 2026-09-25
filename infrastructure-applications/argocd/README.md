# Argo CD (Helm)

This module installs [Argo CD](https://argo-cd.readthedocs.io/) so the
cluster can sync Applications from Git. It is an **infrastructure
application**, not a complement: it does not replace CNI, IAM, or the
node group.

It does not use IRSA. Argo CD talks to the Kubernetes API (in-cluster
RBAC from the chart) and to Git. Image pulls use the node role, which
already has ECR read. Add an IAM role later only if a repo-server or
the application controller must call AWS APIs (cross-account deploy,
CodeCommit).

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium. Optional UI Ingress also assumes the AWS Load Balancer
Controller and IngressClass `alb`.

See [`../README.md`](../README.md) for how this tree differs from
complements.

---

## 1. What problem this solves

kubectl apply from a laptop does not record the desired state of
applications. Argo CD does: an `Application` CR points at a Git path,
and the controllers reconcile the cluster to that commit.

| Workload | Role |
|---|---|
| `argocd-server` | UI and API |
| `argocd-application-controller` | Sync and health |
| `argocd-repo-server` | Render Helm/Kustomize/manifests |
| `argocd-redis` | Cache |
| `argocd-applicationset-controller` | Generate Applications from a generator |
| `argocd-notifications-controller` | Optional (on by default) |
| `argocd-dex-server` | Off until SSO is configured |

---

## 2. Why Helm (not an EKS add-on)

The documented install is the community chart `argo-cd` from
`https://argoproj.github.io/argo-helm`. Chart **10.9.2**. Terraform
manages it the same way as KEDA: one module, Helm in `main.tf`,
providers at the root.

Do not also install another Argo CD (a second Helm release or an EKS
add-on). Two controllers fight over the same CRDs.

CRDs are installed by the chart (`crds.install: true`) and kept on
uninstall (`crds.keep: true`) so deleting the release does not drop
Application history.

---

## 3. Apply order

```
complements/networking/cilium
complements/loadbalancing/lbc     only required when ingress_enabled
infrastructure-applications/argocd
    helm_release.this
```

Root wiring in this repo (Karpenter selector so the system pool is not packed):

```hcl
module "argocd" {
  source = "../infrastructure-applications/argocd"

  chart_version = var.argocd_chart_version

  node_selector = {
    "karpenter.sh/nodepool" = "default"
  }

  depends_on = [module.cilium, module.lbc, module.karpenter]
}
```

The module default selector is only `kubernetes.io/os=linux`, so a cluster
without Karpenter can omit `node_selector`. On Alesia the managed
`t3.medium` pool is already full of platform pods (Cilium ENI IP limits).
The selector above leaves Argo CD unschedulable there so Karpenter can
provision a node.

---

## 4. Ingress

`ingress_enabled` defaults to **false**. Reach the UI with port-forward
(the server keeps its own TLS):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Open `https://localhost:8080` and accept the self-signed certificate.

To publish an ALB, set both knobs. `ingress_hostname` is required: the
chart always writes a host rule, and an empty host becomes
`argocd.example.com`, which the ALB will not match.

```hcl
ingress_enabled  = true
ingress_hostname = "argocd.example.com"
```

That turns on `server.insecure` (ALB speaks HTTP to the pod),
`target-type: ip` (Cilium ENI), and backend protocol HTTP. TLS at the
ALB and a DNS record are not part of this module.

---

## 5. How to verify

```bash
kubectl -n argocd get deploy,sts
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

User is `admin`. The initial password lives in that Secret, not in
Terraform state. Rotate it in the UI or with `argocd account update-password`, then delete the initial Secret.

```bash
argocd login localhost:8080 --username admin --password '<password>' --insecure
argocd app list
```

---

## 6. What this module does not do

- Register Git repositories, Projects, or Applications (those are GitOps
  content, not the installer).
- SSO / Dex connectors (`dex_enabled` defaults to false).
- IRSA, CodeCommit, or cross-account cluster credentials.
- A public ALB, unless `ingress_enabled` and `ingress_hostname` are set.
- HA Redis (`redis-ha` stays off).
