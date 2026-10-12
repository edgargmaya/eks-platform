# Infrastructure applications

These modules install **cluster applications**, not platform
capabilities. Complements (`../complements`) are CNI, storage, load
balancing, and autoscaling. This tree is for tools that run *on* that
platform and manage or serve workloads.

| Module | Role |
|---|---|
| [`argocd`](argocd) | Argo CD (GitOps). Helm chart, no IRSA. |
| [`vault`](vault) | Vault HA, Integrated Storage (Raft), KMS auto-unseal, dedicated Karpenter pool. |

Add a module here when the responsibility is a platform application
workloads depend on (GitOps, secrets), not a cluster capability such
as CNI or the External Secrets Operator.

Root wiring: [`../eks-implementation`](../eks-implementation).
Providers stay there. These modules apply **after** Cilium. Argo CD’s
optional ALB Ingress also waits for the load balancer controller.
