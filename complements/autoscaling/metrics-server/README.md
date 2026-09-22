# metrics-server (Helm)

This module is the **resource-metrics complement**. It installs the
upstream [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
so the Kubernetes Metrics API (`metrics.k8s.io`) can serve pod and node
CPU/memory. KEDA CPU/memory triggers, and stock HPA, read that API.

It does not live in `modules/cluster`. It does not use IRSA: metrics-server
only talks to kubelet and the Kubernetes API.

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium and **before** KEDA. The Deployment needs a working CNI.
KEDA’s CPU/memory scalers fail without this APIService.

This is **not** KEDA’s own `keda-operator-metrics-apiserver` (external
metrics). That process comes from the KEDA chart. This module is the
cluster metrics-server.

See [`../../README.md`](../../README.md) for how complements differ from
the control plane.

---

## 1. What problem this solves

Without metrics-server, `kubectl top` is empty and HPA/KEDA cannot
evaluate `type: cpu` / `type: memory`. Other KEDA triggers (cron, SQS,
Prometheus) do not need this component.

| Consumer | API |
|---|---|
| `kubectl top`, Dashboard, HPA resource metrics | `metrics.k8s.io` (this module) |
| KEDA ScaledObject CPU / memory | same, via the HPA it creates |
| KEDA ScaledObject cron / SQS / Prometheus | KEDA metrics API / scaler logic, not this chart |

---

## 2. Why Helm (not `aws_eks_addon`)

EKS publishes a **community** add-on named `metrics-server`. This
platform still installs it with Helm, same as KEDA and LBC:

- `--kubelet-insecure-tls` is a first-class value. EKS kubelet serving
  certs are not signed by a CA metrics-server trusts; without that flag
  scrapes fail and the API stays empty.
- Chart **3.14.0** tracks metrics-server **0.9.0** (Kubernetes 1.34+).
  Bump `chart_version` when you upgrade.

Do **not** also enable the EKS community add-on. Two metrics-servers
fight over `v1beta1.metrics.k8s.io`.

If a previous **manual** Helm install already exists in `kube-system`:

```bash
helm -n kube-system uninstall metrics-server
```

Then apply Terraform so this module owns the release.

---

## 3. Apply order (one Terraform graph)

```
complements/networking/cilium
complements/autoscaling/metrics-server
    helm_release.this              chart + APIService
complements/autoscaling/keda
```

Root wiring:

```hcl
module "metrics_server" {
  source = "../complements/autoscaling/metrics-server"

  chart_version = var.metrics_server_chart_version

  depends_on = [module.cilium]
}

module "keda" {
  source = "../complements/autoscaling/keda"

  # ...
  depends_on = [module.cilium, module.metrics_server]
}
```

---

## 4. EKS / Cilium notes

| Setting | Why |
|---|---|
| `args: [--kubelet-insecure-tls]` | EKS kubelet HTTPS is not verifiable with the cluster CA. |
| `hostNetwork.enabled: false` | Cilium ENI gives pods VPC IPs; the API server reaches the Service. |
| Namespace `kube-system` | Upstream default; `priorityClassName: system-cluster-critical`. |

No IAM role. The chart RBAC is enough to list nodes/pods and get kubelet
summary stats.

---

## 5. How to verify

```bash
kubectl -n kube-system get deploy metrics-server
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
```

`APISERVICE` should be `True`. `kubectl top` should print CPU and memory
within about a minute of the Deployment becoming Ready.

---

## 6. What this module does not do

- KEDA (sibling complement; consumes this API for CPU/memory only).
- Prometheus, kube-state-metrics, or custom metrics adapters.
- The EKS community `metrics-server` add-on.
