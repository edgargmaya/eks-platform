# Infrastructure applications

These modules install **cluster applications**, not platform
capabilities. Complements (`../complements`) are CNI, storage, load
balancing, and autoscaling. This tree is for tools that run *on* that
platform and manage or serve workloads.

| Module | Role |
|---|---|
| [`argocd`](argocd) | Argo CD (GitOps). Helm chart, no IRSA. |

Add a module here when the responsibility is an application (GitOps,
CI, dashboards), not when it is cluster infrastructure.

Root wiring: [`../eks-implementation`](../eks-implementation).
Providers stay there. These modules apply **after** Cilium. Argo CD’s
optional ALB Ingress also waits for the load balancer controller.
