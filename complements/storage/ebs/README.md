# Amazon EBS CSI on EKS (managed add-on + IRSA)

This module is the **storage complement** for block volumes. It does not
live in `modules/cluster`. Cluster-level IRSA enablement (the IAM OIDC
identity provider) already exists in
[`../../../modules/cluster/irsa.tf`](../../../modules/cluster/irsa.tf).
This module only declares **this add-on’s** IAM:

1. An IAM role trusted by this cluster’s OIDC provider, scoped to
   `kube-system/ebs-csi-controller-sa`, with `AmazonEBSCSIDriverPolicyV2`.
2. The **Amazon EBS CSI Driver** as an **EKS managed add-on**, with
   `service_account_role_arn` so EKS annotates that ServiceAccount
   (`eks.amazonaws.com/role-arn`).
3. A default **`gp3` StorageClass** (`ebs.csi.aws.com`, encrypted,
   `WaitForFirstConsumer`).

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium (`depends_on = [module.cilium]`): the CSI *controller*
is a regular Deployment and needs a working CNI.

See [`../../README.md`](../../README.md) for how complements differ from
the control plane.

---

## 1. What problem this solves

Kubernetes does not provision Amazon EBS volumes by itself. A **CSI
driver** watches PersistentVolumeClaims, calls EC2, attaches the volume
to the right node, and mounts it into the pod.

Until Kubernetes 1.27 the in-tree provisioner `kubernetes.io/aws-ebs`
did that (the old `gp2` StorageClass on many EKS clusters). That code
is gone. From EKS 1.30, new clusters **no longer** mark `gp2` as the
default StorageClass. Without this complement, a PVC with
`storageClassName: ""` (or omitted, expecting a default) stays
`Pending` forever.

The Amazon EBS CSI driver splits in two:

| Workload | Runs where | Needs AWS API? |
|---|---|---|
| `ebs-csi-controller` (Deployment) | Any node, **pod network** | **Yes** — CreateVolume, Attach, Modify, Delete |
| `ebs-csi-node` (DaemonSet) | Every node | **No** IAM for EC2. Formats and mounts the device kubelet already attached |

Only the controller service account (`ebs-csi-controller-sa` in
`kube-system`) gets an IAM role. Giving the node DaemonSet the same
role would widen the blast radius for no gain.

---

## 2. Why a managed add-on (not a Helm chart we own)

AWS’s documented install for EBS CSI on EKS is the **managed add-on**
`aws-ebs-csi-driver`:

- EKS pins a driver build compatible with the cluster’s Kubernetes
  minor version (`data.aws_eks_addon_version` + `most_recent`).
- EKS owns RBAC, the controller Deployment, the node DaemonSet, and
  upgrades when you change `addon_version`.
- `service_account_role_arn` is the IRSA path: EKS creates
  `ebs-csi-controller-sa` and annotates it with the role. This module
  does **not** set `pod_identity_association`.

A self-managed Helm chart of `kubernetes-sigs/aws-ebs-csi-driver` still
works. It is more moving parts (chart version, image tags, RBAC drift)
for the same EC2 API. This platform uses the add-on and IRSA.

---

## 3. Apply order (one Terraform graph)

Providers stay in the root. This module needs AWS (add-on, IAM) and
Helm (StorageClass only).

```
modules/cluster/irsa.tf               IAM OIDC provider (cluster-wide IRSA)
complements/networking/cilium         CNI must be Ready for controller pods
complements/storage/ebs
    iam.tf                         IRSA role + managed policy
    aws_eks_addon.ebs_csi          service_account_role_arn
    helm_release.gp3              StorageClass
```

Root wiring:

```hcl
module "ebs" {
  source = "../complements/storage/ebs"

  cluster_name           = module.cluster.cluster_name
  cluster_version        = var.cluster_version
  oidc_provider_arn     = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath

  depends_on = [module.cilium]
}
```

If the CSI controller is created while Cilium agents are still
CrashLooping, its pods sit `Pending` (`FailedCreatePodSandBox`) until
CNI works, then recover. Sequencing after Cilium avoids that window
on a clean apply.

`terraform apply --auto-approve` does not need kubeconfig. Helm uses
the same `aws eks get-token` exec authenticator as Cilium.

---

## 4. IRSA for this add-on (not Pod Identity)

Cluster OIDC registration is **not** this module’s job. Complements
only consume `oidc_provider_arn` and `oidc_provider_hostpath`.

This platform uses IRSA for add-ons (same pattern as Cilium ENI IPAM)
so workload identity stays OIDC-based and portable. EKS Pod Identity
(`pods.eks.amazonaws.com` + `eks-pod-identity-agent`) is not used here.

Do **not** set both `service_account_role_arn` and
`pod_identity_association` on the add-on.

### 4.1 How a credential request flows

1. The controller pod uses `ebs-csi-controller-sa`.
2. The AWS SDK sees `AWS_ROLE_ARN` / `AWS_WEB_IDENTITY_TOKEN_FILE`
   from the projected ServiceAccount token (IRSA).
3. The SDK calls `sts:AssumeRoleWithWebIdentity` against the role whose
   ARN is on the ServiceAccount annotation.
4. IAM checks the trust policy: federated principal = this cluster’s
   OIDC provider, `sub` = that ServiceAccount, `aud` = STS.

EKS creates and annotates `ebs-csi-controller-sa` when the add-on is
applied with `service_account_role_arn`. You do not pre-create the
ServiceAccount in Terraform for this managed add-on.

### 4.2 Trust policy (least privilege)

[`iam.tf`](iam.tf) requires:

| Condition | Effect |
|---|---|
| Principal = this cluster’s OIDC provider | Another cluster’s issuer cannot assume the role |
| `:sub` = `system:serviceaccount:kube-system:ebs-csi-controller-sa` | Only that ServiceAccount |
| `:aud` = `sts.<partition dns>` | Standard IRSA audience |

### 4.3 Managed policy

`AmazonEBSCSIDriverPolicyV2` (`arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2`)
is the policy AWS documents for new installs. It is **not** under
`service-role/` (that prefix belongs to the older
`AmazonEBSCSIDriverPolicy`). V2 scopes mutations to volumes tagged
`ebs.csi.aws.com/cluster=true`, which the driver sets on volumes it
creates. Custom CMKs are **not** in that policy; pass `kms_key_arn`
and the module attaches an extra inline policy (`CreateGrant` only
when `kms:GrantIsForAWSResource=true`, plus Encrypt / Decrypt /
GenerateDataKey / DescribeKey on that key).

---

## 5. The managed add-on

[`main.tf`](main.tf) uses `data.aws_eks_addon_version` with
`most_recent = true` for this cluster’s Kubernetes minor version, then:

```hcl
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = aws_iam_role.controller.arn

  configuration_values = jsonencode({
    defaultStorageClass = { enabled = false }
  })
}
```

`resolve_conflicts_on_create/update = OVERWRITE` means Terraform’s
values win over leftover kubectl edits.

`defaultStorageClass.enabled = false` because the add-on’s built-in
class (`ebs-csi-default-sc`) does not expose encryption / KMS the way
this platform wants. The module creates `gp3` itself (section 6).
Enabling both would fight over “which class is default”.

---

## 6. StorageClass `gp3`

Helm chart [`charts/gp3-storageclass`](charts/gp3-storageclass)
(cluster-scoped object; Helm release still lives in `kube-system`):

| Field | Value | Why |
|---|---|---|
| `provisioner` | `ebs.csi.aws.com` | In-tree `kubernetes.io/aws-ebs` is gone. Auto Mode uses a different provisioner; this cluster is not Auto Mode. |
| `type` | `gp3` | Default EBS type; cheaper than gp2 for the same baseline. |
| `encrypted` | `true` | Always-on encryption. AWS-managed `aws/ebs` unless `kms_key_arn` is set. |
| `volumeBindingMode` | `WaitForFirstConsumer` | Volume is created in the **AZ of the pod**, not a random AZ (EBS cannot attach across AZs). |
| `allowVolumeExpansion` | `true` | PVC can grow; EBS CSI calls ModifyVolume. |
| `reclaimPolicy` | `Delete` | Deleting the PVC deletes the volume. Change to `Retain` only if you need to keep data after PVC delete. |
| default annotation | `true` unless disabled | Bare `volumeClaimTemplates` without a class name work. |

`WaitForFirstConsumer` is not optional for a multi-AZ node group. Immediate
binding would create a volume in AZ-a and a pod scheduled in AZ-b, then
AttachVolume would fail forever.

---

## 7. Timeline of one apply (new cluster)

Assume bootstrap + cluster definition + Cilium already succeeded.

1. **IAM role** `<cluster>-ebs-csi-controller` with IRSA trust
   (`AssumeRoleWithWebIdentity` + TagSession) and
   `AmazonEBSCSIDriverPolicyV2`. Optional KMS inline policy.
2. **Add-on `aws-ebs-csi-driver`.** EKS creates controller + node
   plugin + SA, and annotates the SA with the role. Terraform waits
   until the add-on is `ACTIVE` (pods must schedule — CNI is already
   Cilium).
3. **Helm `ebs-gp3-storageclass`.** `kubectl get sc gp3` shows
   `(default)`.

Failure in 2 fails the apply. There is no laptop `kubectl` step.

If this stack previously installed `eks-pod-identity-agent` under
this module, the next apply **destroys that add-on**. That is
intentional: later complements must not depend on Pod Identity.

---

## 8. How to verify

```bash
aws eks describe-addon --cluster-name <cluster> --addon-name aws-ebs-csi-driver

kubectl -n kube-system get deploy ebs-csi-controller
kubectl -n kube-system get ds ebs-csi-node
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml
# metadata.annotations["eks.amazonaws.com/role-arn"] must match the role

kubectl get sc
# gp3 (default)   ebs.csi.aws.com   WaitForFirstConsumer   true
```

Smoke test (deletes the volume on PVC delete):

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-smoke
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc ebs-smoke   # Bound
kubectl delete pvc ebs-smoke
```

`Pending` + `UnauthorizedOperation` on the PVC events means the
IRSA trust, annotation, or IAM policy is wrong — not the StorageClass.

---

## 9. Recreating the cluster

Destroy `eks-implementation` and apply again. Order:

1. Cluster definition (IAM, EKS, OIDC provider, nodes).
2. Cilium cutover + ENI CNI.
3. This module: IRSA role → CSI add-on → `gp3`.

A second AWS account needs the same root `depends_on` and AWS
credentials. No kubeconfig.

---

## 10. What this module does not do

- Register the cluster OIDC issuer in IAM (that is
  `modules/cluster/irsa.tf`).
- EFS CSI, FSx, or instance-store volumes.
- CSI **snapshot** controller / `VolumeSnapshot` CRDs (required before
  EBS snapshots via CSI). Add that as its own complement if needed.
- EKS Auto Mode storage (`ebs.csi.eks.amazonaws.com`).
- Fargate or Windows nodes.
- Changing the node instance role. Nodes still have
  `AmazonEKSWorkerNodePolicy`; they do not need
  `AmazonEBSCSIDriverPolicy` on the instance profile.
- `eks-pod-identity-agent`. Do not re-add it for later complements.
