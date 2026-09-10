# AWS Load Balancer Controller (Helm + IRSA)

This module is the **load-balancing complement**. It does not live in
`modules/cluster`. Cluster-level IRSA enablement (the IAM OIDC identity
provider) already exists in
[`../../../modules/cluster/irsa.tf`](../../../modules/cluster/irsa.tf).
This module only declares **this add-on’s** IAM and install:

1. An IAM role trusted by this cluster’s OIDC provider, scoped to
   `kube-system/aws-load-balancer-controller`.
2. The official controller IAM policy (customer-managed; AWS does not
   publish an `AWSLoadBalancerController*` managed policy).
3. The **AWS Load Balancer Controller** Helm chart from
   `https://aws.github.io/eks-charts`, with
   `eks.amazonaws.com/role-arn` on the ServiceAccount Helm creates.

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium (`depends_on = [module.cilium]`): the controller is a
regular Deployment and needs a working CNI.

See [`../../README.md`](../../README.md) for how complements differ from
the control plane.

---

## 1. What problem this solves

Without this controller, Kubernetes `Service` `type: LoadBalancer` uses
the **legacy in-tree cloud provider**, which provisions **Classic Load
Balancers**. Ingress has no AWS ALB implementation at all.

This controller watches:

| Kubernetes object | AWS resource |
|---|---|
| `Ingress` with `ingressClassName: alb` | Application Load Balancer |
| `Service` `type: LoadBalancer` (mutator webhook) | Network Load Balancer |

Subnet discovery is already in bootstrap: public subnets have
`kubernetes.io/role/elb=1`, private have
`kubernetes.io/role/internal-elb=1`, and the cluster module tags both
`kubernetes.io/cluster/<name>=shared`. Control-plane `/28`s are not
tagged for ELB on purpose.

---

## 2. Why Helm (not `aws_eks_addon`)

EBS CSI is an Amazon EKS managed add-on (`aws-ebs-csi-driver`). The
Load Balancer Controller is **not**. `DescribeAddonVersions` in
`us-east-1` does not return `aws-load-balancer-controller` (the only
ingress-related add-on in the catalog is a Marketplace HAProxy chart).

AWS’s documented install for non–Auto Mode clusters is the Helm chart
`eks/aws-load-balancer-controller`. Terraform manages that the same way
this platform manages Cilium: one complement, IRSA in `iam.tf`, Helm
in `main.tf`, providers stay at the root.

Do **not** set Pod Identity on this workload. IRSA is the platform
standard.

Helm chart **3.5.0** tracks controller **v3.5.0**. Bump
`chart_version` and refresh [`iam-policy.json`](iam-policy.json) from
the matching GitHub tag when you upgrade.

---

## 3. Apply order (one Terraform graph)

```
modules/cluster/irsa.tf               IAM OIDC provider (cluster-wide IRSA)
complements/networking/cilium         CNI must be Ready for controller pods
complements/loadbalancing/lbc
    iam.tf                         IRSA role + customer-managed policy
    helm_release.this              chart + SA annotation
```

Root wiring:

```hcl
module "lbc" {
  source = "../complements/loadbalancing/lbc"

  cluster_name           = module.cluster.cluster_name
  aws_region             = var.aws_region
  vpc_id                 = local.vpc_id
  oidc_provider_arn      = module.cluster.oidc_provider_arn
  oidc_provider_hostpath = module.cluster.oidc_provider_hostpath

  depends_on = [module.cilium]
}
```

`vpcId` and `region` are set in values so the controller does not need
IMDS to discover the VPC. Credentials still come from IRSA.

---

## 4. IRSA for this add-on

[`iam.tf`](iam.tf) requires:

| Condition | Effect |
|---|---|
| Principal = this cluster’s OIDC provider | Another cluster’s issuer cannot assume the role |
| `:sub` = `system:serviceaccount:kube-system:aws-load-balancer-controller` | Only that ServiceAccount |
| `:aud` = `sts.<partition dns>` | Standard IRSA audience |

Unlike EBS CSI, there is no AWS-managed policy to attach. The JSON in
[`iam-policy.json`](iam-policy.json) is the project’s
`docs/install/iam_policy.json` (ELB, EC2 security groups, ACM, WAF,
Shield). Scope mutations with `elbv2.k8s.aws/cluster` tag conditions.

Helm creates the ServiceAccount and annotates it. The IRSA `sub` must
keep matching `service_account_name`.

---

## 5. Cilium ENI and target type

This cluster is Cilium **ENI** + native routing (`bpf.masquerade:
false`). Pods have real VPC IPs. The chart default
`defaultTargetType: instance` is for overlay CNIs. This module sets
**`ip`** so ALB/NLB target groups register pod IPs, not NodePorts.

Internet-facing ALBs still land on public `/26`s (`role/elb=1`).
Internal LBs use private `/19`s (`role/internal-elb=1`).

---

## 6. Timeline of one apply

Assume bootstrap + cluster definition + Cilium already succeeded.

1. **IAM role** `<cluster>-aws-load-balancer-controller` with IRSA
   trust and the vendored policy.
2. **Helm** installs CRDs, Deployment (2 replicas), webhooks, and
   IngressClass `alb`. Terraform waits until the release is ready.

The service mutator webhook stays **on** (chart default): new
`Service` `type: LoadBalancer` objects get
`spec.loadBalancerClass: service.k8s.aws/nlb`. Existing Classic LBs
are not migrated.

---

## 7. How to verify

```bash
kubectl -n kube-system get deploy aws-load-balancer-controller
kubectl -n kube-system get sa aws-load-balancer-controller -o yaml
# metadata.annotations["eks.amazonaws.com/role-arn"] must match the role

kubectl get ingressclass alb
```

Smoke test (needs a workload and a public hostname/path you control):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lbc-smoke
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <your-service>
                port:
                  number: 80
```

`kubectl describe ingress` stuck without a hostname usually means IAM
(trust/policy) or missing subnet role tags — not Helm.

---

## 8. What this module does not do

- Register the cluster OIDC issuer in IAM (`modules/cluster/irsa.tf`).
- Tag subnets (bootstrap already does).
- cert-manager (the chart ships a self-signed webhook cert).
- Gateway API feature gates (optional on controller v3; off by
  default).
- ExternalDNS / ACM certificate automation beyond the IAM actions in
  the official policy.
