# Karpenter (Helm + IRSA)

This module is the **cluster-autoscaling complement** (nodes, not pods).
It does not live in `modules/cluster` or `modules/nodegroup`. Cluster-level
IRSA enablement already exists in
[`../../../modules/cluster/irsa.tf`](../../../modules/cluster/irsa.tf).

The **managed node group stays**. It is the system pool (Cilium, LBC,
metrics-server, KEDA, this controller). Karpenter launches **additional**
EC2 instances for unschedulable workloads. It does not scale the managed
node group ASG.

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium.

See [`../../README.md`](../../README.md) for how complements differ from
the control plane.

---

## 1. What problem this solves

KEDA scales **pods**. When those pods do not fit on the two `t3.medium`
system nodes (ENI IP exhaustion, CPU, memory), they stay `Pending`.
Karpenter watches unschedulable pods and calls EC2 `CreateFleet`.

| Pool | Who | Size |
|---|---|---|
| Managed NG `alesia-workers` | Terraform `modules/nodegroup` | Small, static |
| Karpenter NodePool `default` | This module | On-demand Nitro `c`/`m`, 2–8 vCPU, CPU limit |

Do **not** install Cluster Autoscaler on the same NG.

---

## 2. Why Helm (not `aws_eks_addon`)

The documented install is the OCI chart
`oci://public.ecr.aws/karpenter/karpenter`. Chart **1.14.1**.

---

## 3. AWS pieces (not Kubernetes)

| Resource | Why |
|---|---|
| IRSA role `<cluster>-karpenter` | Controller EC2/IAM/SQS/EKS APIs. Trust = `karpenter/karpenter`. Policies match the upstream CloudFormation (scoped tags `kubernetes.io/cluster/<name>=owned`). |
| Instance profile `<cluster>-karpenter-nodes` | Reuses the **existing** node IAM role so the EKS Access Entry (`EC2_LINUX`) already allows join. No `aws-auth`. |
| SQS `<cluster>-karpenter` + EventBridge | Spot interruption, rebalance, instance state, health. |

---

## 4. Cilium ENI

Helm `settings.reservedENIs: "1"` matches Cilium
`eni.nodeSpec.firstInterfaceIndex: 1` (primary ENI is the node, not
pods). Without this, Karpenter’s max-pods math assumes VPC CNI and
over-schedules — the same `all CIDR ranges are exhausted` seen on
`t3.medium`.

`EC2NodeClass`:

- Subnets: `kubernetes.io/role/internal-elb=1` **and**
  `kubernetes.io/cluster/<name>=shared` (private `/19` only).
- Security group: cluster SG by id.
- `httpPutResponseHopLimit: 2`, `httpTokens: required` (IRSA / IMDS).
- AMI alias `al2023@latest` (Karpenter writes AL2023 `NodeConfig`).
- Encrypted gp3 root volume.

NodePool: on-demand, Nitro, categories `c`/`m`, generation > 2, 2/4/8
vCPU (not `t3.medium`). Consolidation
`WhenEmptyOrUnderutilized` / `1m`.

---

## 5. Apply order

```
modules/cluster/irsa.tf
complements/networking/cilium
complements/autoscaling/karpenter
    interruption.tf   SQS + EventBridge
    iam.tf             IRSA + instance profile
    helm_release.this  controller
    helm_release.nodeclass   EC2NodeClass + NodePool
```

Root:

```hcl
module "karpenter" {
  source = "../complements/autoscaling/karpenter"

  cluster_name               = module.cluster.cluster_name
  cluster_endpoint            = module.cluster.cluster_endpoint
  cluster_security_group_id  = module.cluster.cluster_security_group_id
  oidc_provider_arn         = module.cluster.oidc_provider_arn
  oidc_provider_hostpath    = module.cluster.oidc_provider_hostpath
  node_role_name             = module.iam.node_role_name
  node_role_arn              = module.iam.node_role_arn

  depends_on = [module.cilium]
}
```

---

## 6. How to verify

```bash
kubectl -n karpenter get deploy,sa
kubectl get nodepool,ec2nodeclass
kubectl -n karpenter logs deploy/karpenter -c controller --tail=50
```

Smoke (unschedulable pause pods; delete when done so nodes consolidate):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 10
  selector:
    matchLabels: { app: inflate }
  template:
    metadata:
      labels: { app: inflate }
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
          resources:
            requests:
              cpu: "1"
              memory: 1Gi
```

A `karpenter.sh/nodepool=default` node should appear, Cilium Ready, pods
Running. `kubectl delete deploy inflate` then wait: Karpenter should
terminate the empty node.

---

## 7. What this module does not do

- Shrink the managed NG (`node_max_size`). Leave min=desired=2; set
  max=2 yourself if you want the ASG unable to grow.
- Cluster Autoscaler.
- Spot (no Spot service-linked role required). Add
  `karpenter.sh/capacity-type=spot` later if needed.
- Tag bootstrap subnets with `karpenter.sh/discovery` (existing ELB +
  cluster tags are enough).
