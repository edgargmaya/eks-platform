# Vault (Helm, Raft, KMS auto-unseal)

This module runs a **3-node Vault cluster** on the EKS cluster, with
Integrated Storage (Raft). It is an infrastructure application: future
microservices need a secrets platform, and this is that platform.

External Secrets Operator is **not** here. It lives in
[`../../complements/secrets/external-secrets`](../../complements/secrets/external-secrets)
so the Kubernetes integration can point at Vault today and another
provider later.

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium, the EBS CSI driver, and Karpenter. Karpenter must be
running: Vault pods do not schedule on the system node group.

---

## 1. What this installs

| Piece | Why |
|---|---|
| KMS key `<cluster>-vault-unseal` | Auto-unseal. A rescheduled pod unseals itself. This is not the EKS secrets key. |
| IRSA role `<cluster>-vault` | `kms:Encrypt`, `kms:Decrypt`, `kms:DescribeKey` on that key only. |
| NodePool `vault` | Taint `dedicated=vault:NoSchedule`. On-demand Nitro `c`/`m`, 2 vCPU. `expireAfter: Never`. Consolidation only when the node is empty. Reuses EC2NodeClass `default`. |
| StorageClass `vault-gp3` | gp3, encrypted, `WaitForFirstConsumer`, **Retain**. |
| Helm `vault` 0.34.1 | HA Raft, 3 replicas, injector and CSI **off**. |

The agent injector and the CSI provider are off so External Secrets
stays the only way applications read secrets.

Pods select `karpenter.sh/nodepool=vault` and tolerate the taint.
Hostname anti-affinity puts one Vault pod on each node, so Karpenter
launches three nodes. Zone spread prefers one pod per AZ.

---

## 2. Why Terraform does not wait

A sealed Vault fails its readiness probe. `wait = true` would time out
and, with `atomic`, uninstall the release before anyone can run
`operator init`. This module applies the chart and returns. Initialize
once, by hand, and do not put the root token in Terraform state.

---

## 3. Initialize once

After the pods exist (they stay unready until init):

```bash
kubectl -n vault exec vault-0 -- vault operator init
```

With the KMS seal this prints **recovery keys** and a root token, not
Shamir unseal keys. Store them outside the cluster. Followers join
through `retry_join` and unseal via KMS. Then:

```bash
kubectl -n vault exec vault-0 -- vault status
kubectl -n vault exec vault-0 -- vault operator raft list-peers
```

Three peers, one leader. The UI stays ClusterIP:

```bash
kubectl -n vault port-forward svc/vault-ui 8200:8200
```

The listener has `tls_disable = 1`. Do not turn this Service into a
public LoadBalancer. End-to-end TLS is a later change.

---

## 4. What this module does not do

- `vault operator init`, or storing the root token.
- Kubernetes auth, policies, or a `ClusterSecretStore` (that is ESO,
  after init).
- Listener TLS.
- Consul.
- The agent injector and the Vault CSI provider.
