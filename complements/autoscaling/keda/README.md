# KEDA (Helm + IRSA)

This module is the **pod-autoscaling complement**. It does not live in
`modules/cluster`. Cluster-level IRSA enablement already exists in
[`../../../modules/cluster/irsa.tf`](../../../modules/cluster/irsa.tf).
This module only declares **this add-on’s** IAM and install:

1. An IAM role trusted by this cluster’s OIDC provider, scoped to
   `keda/keda-operator`.
2. The **KEDA** Helm chart from `https://kedacore.github.io/charts`,
   with `podIdentity.aws.irsa` so the chart annotates that
   ServiceAccount (`eks.amazonaws.com/role-arn`).

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium (`depends_on = [module.cilium]`): operator, metrics
API, and webhook pods need a working CNI.

See [`../../README.md`](../../README.md) for how complements differ from
the control plane.

This is **not** cluster autoscaling (Karpenter / Cluster Autoscaler).
KEDA scales **pods** (and jobs) from events and metrics. Node capacity
is a separate complement.

---

## 1. What problem this solves

Horizontal Pod Autoscaler only understands CPU/memory (and custom
metrics if you wire an adapter). KEDA adds:

| Object | Job |
|---|---|
| `ScaledObject` | Scale a Deployment / StatefulSet from a trigger (cron, SQS, Prometheus, …) by driving an HPA |
| `ScaledJob` | Run Jobs from a queue depth |
| `TriggerAuthentication` | How the scaler authenticates (IRSA, Secret, …) |

Three workloads, one Helm release:

| Workload | SA | Needs AWS? |
|---|---|---|
| `keda-operator` | `keda-operator` | **Only** if an AWS scaler uses `identityOwner: keda` |
| `keda-operator-metrics-apiserver` | `keda-metrics-server` | No — Kubernetes external metrics API |
| `keda-admission-webhooks` | `keda-webhook` | No |

Only the operator ServiceAccount is bound to the IAM role.

---

## 2. Why Helm (not `aws_eks_addon`)

`DescribeAddonVersions` does not list KEDA. The documented install is
the official Helm chart `kedacore/keda`. Terraform manages it the
same way as Cilium and LBC: one complement, IRSA in `iam.tf`, Helm in
`main.tf`, providers at the root.

Chart **2.20.2** tracks KEDA **2.20.2**. Bump `chart_version` when you
upgrade.

---

## 3. Apply order (one Terraform graph)

```
modules/cluster/irsa.tf               IAM OIDC provider (cluster-wide IRSA)
complements/networking/cilium         CNI must be Ready
complements/autoscaling/keda
    iam.tf                         IRSA role (+ optional scaler policy)
    helm_release.this              chart + IRSA annotations
```

Root wiring:

```hcl
module "keda" {
  source = "../complements/autoscaling/keda"

  cluster_name           = module.cluster.cluster_name
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath

  depends_on = [module.cilium]
}
```

---

## 4. IRSA for this add-on

[`iam.tf`](iam.tf) requires:

| Condition | Effect |
|---|---|
| Principal = this cluster’s OIDC provider | Another cluster’s issuer cannot assume the role |
| `:sub` = `system:serviceaccount:keda:keda-operator` | Only that ServiceAccount |
| `:aud` = `sts.<partition dns>` | Standard IRSA audience |

There is **no** AWS-managed `KEDA*` policy. Core KEDA talks to the
Kubernetes API (RBAC from the chart), not to AWS.

AWS scalers (SQS, CloudWatch, DynamoDB, …) need extra IAM on **this
same role** when the ScaledObject uses `identityOwner: keda`. Pass
`operator_iam_policy_json` or attach a policy to
`<cluster>-keda-operator` later. Least privilege is per queue/metric,
not a platform-wide `sqs:*`.

Prefer **workload IRSA** (`identityOwner: workload`) for app-specific
queues so the operator role stays empty.

Helm `podIdentity.aws.irsa` annotates `keda-operator` only. Do not
put the same role on the metrics or webhook SAs.

---

## 5. Timeline of one apply

Assume bootstrap + cluster definition + Cilium already succeeded.

1. **IAM role** `<cluster>-keda-operator` with IRSA trust.
2. **Helm** creates namespace `keda`, CRDs, operator, metrics API,
   webhooks. Terraform waits until the release is ready.

`metrics-server` is **not** this module. CPU/memory triggers need it;
cron / SQS / Prometheus do not.

---

## 6. How to verify

```bash
kubectl -n keda get deploy
kubectl -n keda get sa keda-operator -o yaml
# metadata.annotations["eks.amazonaws.com/role-arn"] must match the role

kubectl get crd scaledobjects.keda.sh scaledjobs.keda.sh
```

Smoke test (cron; no AWS credentials). Scale a Deployment to 0 outside
the window and to 1 inside it:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keda-cron-echo
  namespace: default
spec:
  replicas: 0
  selector:
    matchLabels:
      app: keda-cron-echo
  template:
    metadata:
      labels:
        app: keda-cron-echo
    spec:
      containers:
        - name: pause
          image: registry.k8s.io/pause:3.10
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: keda-cron-echo
  namespace: default
spec:
  scaleTargetRef:
    name: keda-cron-echo
  minReplicaCount: 0
  maxReplicaCount: 1
  triggers:
    - type: cron
      metadata:
        timezone: America/Mexico_City
        start: 0 0 * * *
        end: 0 23 * * *
        desiredReplicas: "1"
```

Adjust `start`/`end` to the current hour. `kubectl get hpa` should
show a KEDA-managed HPA. Delete the ScaledObject and Deployment when
done.

---

## 7. What this module does not do

- Register the cluster OIDC issuer (`modules/cluster/irsa.tf`).
- Cluster autoscaling (Karpenter / Cluster Autoscaler).
- `metrics-server` (EKS community add-on; needed only for CPU/memory
  scalers).
- AWS scaler IAM (SQS, CloudWatch, …) until you pass
  `operator_iam_policy_json`.
- Prometheus, Grafana, or ScaledObject catalogs for applications.
