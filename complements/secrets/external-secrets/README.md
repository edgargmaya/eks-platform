# External Secrets Operator (Helm)

This module is the **secrets interface** on the cluster. It installs
[External Secrets Operator](https://external-secrets.io/) so a
`SecretStore` can copy provider secrets into Kubernetes `Secret`
objects.

It does not install Vault, AWS Secrets Manager, or Azure Key Vault.
Those are providers behind a `SecretStore`. Vault itself is
[`../../../infrastructure-applications/vault`](../../../infrastructure-applications/vault).

No IRSA. The operator talks to the Kubernetes API. Credentials for a
provider belong on the `SecretStore` (for Vault, Kubernetes auth after
`vault operator init`), not on this chart.

Wired from [`../../../eks-implementation`](../../../eks-implementation)
**after** Cilium. It does not wait for Vault to be unsealed.

---

## 1. Why it is a complement

Applications should not embed a provider SDK. ESO is the seam:

| Provider | What changes |
|---|---|
| Vault | `SecretStore` `provider: vault` |
| AWS Secrets Manager | `provider: aws` plus an IRSA role on that store |
| Azure Key Vault | `provider: azurekv` |

The Deployments stay the same. Swapping providers is a new store, not
a new platform.

---

## 2. Apply order

```
complements/networking/cilium
complements/secrets/external-secrets
    helm_release.this
```

Vault can install in parallel. A `ClusterSecretStore` comes after
`vault operator init` and after Kubernetes auth is enabled on Vault.
This module does not create that store: a store that points at a sealed
Vault stays `InvalidProviderConfig` and is noise in every apply.

---

## 3. How to verify

```bash
kubectl -n external-secrets get deploy
kubectl get crd secretstores.external-secrets.io clustersecretstores.external-secrets.io externalsecrets.external-secrets.io
```

---

## 4. What this module does not do

- Vault, or any other secrets backend.
- `SecretStore` / `ClusterSecretStore` / `ExternalSecret` objects.
- An IAM role. Add one later only if a store uses AWS APIs.
