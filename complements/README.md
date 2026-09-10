# Complements

Complements are **not** the EKS control plane. They are operational
capabilities the platform needs after the API and nodes exist: CNI,
storage, load balancing, autoscaling, secrets.

`modules/iam`, `modules/cluster`, and `modules/nodegroup` define the
cluster. Complements consume that cluster (OIDC, endpoint, node group)
and talk to Kubernetes. They stay out of the cluster modules so the
control plane recipe does not grow a Helm provider or addon opinions.

IRSA is enabled once on the cluster (`modules/cluster/irsa.tf`: IAM
OIDC provider for the EKS issuer). Each complement that needs AWS APIs
declares its own ServiceAccount contract, IAM role, permission policy,
and OIDC trust (`sub` = that SA). Complements do **not** install
`eks-pod-identity-agent`.

Each **responsibility** is one module (IAM + deploy together), grouped
by area:


| Area              | Module                                       | Role                                              |
| ----------------- | -------------------------------------------- | ------------------------------------------------- |
| Networking        | `[networking/cilium](networking/cilium)`     | Replace VPC CNI + kube-proxy; ENI IPAM IRSA       |
| Storage           | `[storage/ebs](storage/ebs)`                 | EBS CSI managed add-on, IRSA, default gp3          |
| Load balancing    | `[loadbalancing/lbc](loadbalancing/lbc)`   | AWS Load Balancer Controller Helm + IRSA          |
| Pod autoscaling   | `[autoscaling/keda](autoscaling/keda)`       | KEDA Helm + IRSA (operator)                        |
| Cluster scale     | `[autoscaling/karpenter](autoscaling/karpenter)` | Karpenter Helm + IRSA; managed NG stays as system pool |
| Secrets           | —                                            | Later (External Secrets Operator)                 |


Empty folders for the later rows are intentional omissions. Add a module
when that responsibility is implemented, not before.

Root wiring: `[../eks-implementation](../eks-implementation)`. Providers
stay there. Networking complements sequence after nodes. Storage,
load balancing, pod autoscaling, and Karpenter sequence after Cilium
(controller pods need CNI). The managed node group remains the system
pool; Karpenter adds workload nodes.
