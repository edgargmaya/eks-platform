# Cilium on EKS (ENI mode)

This module replaces the default EKS networking stack — **AWS VPC CNI** (`aws-node`)
and **kube-proxy** — with **Cilium** as the only CNI and the kube-proxy
replacement. Pods receive real VPC IPs from secondary ENIs. There is no overlay
tunnel between nodes.

The goal of this document is to explain the *whole* install process,
it means what Terraform does, what Kubernetes does, and what AWS does
underneath.

Companion module: [`../cilium-iam`](../cilium-iam) (IRSA role the operator
uses to create ENIs). Wired from [`../../eks-implementation`](../../eks-implementation).

---

## 1. What problem this solves

An EKS cluster is not “CNI-less” at birth. The control plane always expects
every node to run a CNI plugin. AWS ships two DaemonSets for that:

| DaemonSet | Process on the node | Job |
|---|---|---|
| `aws-node` | `aws-vpc-cni` + `ipamd` | Assigns pod IPs from the node’s ENIs (VPC CNI) |
| `kube-proxy` | iptables or IPVS rules | Implements Kubernetes Services (`ClusterIP`, `NodePort`) |

Those two are enough to run a cluster, but they are not what this platform
wants:

- VPC CNI ties pod density to ENI/IP limits per instance type and does not
  give eBPF policy, Hubble, or kube-proxy replacement.
- kube-proxy programs iptables. Cilium can do the same work in eBPF, with
  fewer conntrack surprises and one datapath to reason about.

So the install is not “add Cilium next to AWS CNI”. It is **a cutover**:
disable the defaults, then let Cilium own CNI + Services + (in this design)
ENI IPAM.

---

## 2. Why EKS cannot start with Cilium

Terraform cannot install Cilium *instead of* VPC CNI on a brand-new cluster
in one atomic step. The sequence is forced by how EKS boots:

1. **`aws_eks_cluster`** creates the control plane. EKS still deploys the
   default add-ons (`vpc-cni`, `kube-proxy`, `coredns`) even though this
   repo does not declare `aws_eks_addon` resources.
2. **Managed node group** launches AL2023 nodes. `nodeadm` (user-data
   `NodeConfig`) joins them. kubelet will not become Ready for *workload*
   pods until a CNI binary exists under `/etc/cni/net.d/`.
3. **`aws-node`** is what writes that CNI config on a stock EKS node. Until
   it runs, CoreDNS stays `Pending` (`FailedCreatePodSandBox` / no IP).
4. Only after nodes exist can Helm talk to the API and install Cilium.

That is the chicken-and-egg: you need *some* CNI for the node to be usable,
then you must **take that CNI away** before Cilium ENI mode will work.
Running both at once is invalid for this design — two plugins would fight
over ENIs, pod IPs, and `/etc/cni/net.d/`.

```
  bootstrap VPC          EKS control plane         managed nodes
  (subnets, NAT, tags)   (API, OIDC, default       (aws-node + kube-proxy
                          add-ons)                  already scheduled)
         |                      |                          |
         +----------------------+--------------------------+
                                |
         terraform apply  (one graph, no kubeconfig, no pause)
                                |
         helm_release.disable_legacy_cni
           Helm (workstation) ──aws eks get-token──► EKS API
           Helm hook Job (on a node, hostNetwork)
             kubectl patch aws-node + kube-proxy  ──► desired=0
                                |
         helm_release.cilium  (depends_on the release above)
           operator + agents + Hubble
                                |
         operator: secondary ENIs + IPs
         agents: eBPF + CNI binary
         CoreDNS / Hubble / app pods get IPs
```

---

## 3. Target datapath (what “Cilium ENI mode” means)

Values live in [`values.yaml.tftpl`](values.yaml.tftpl). The important
combination:

| Setting | Why it is this way |
|---|---|
| `eni.enabled: true` + `ipam.mode: eni` | Operator allocates **secondary ENIs** and IPs from the VPC. Pods are first-class VPC addresses, not `10.0.x` overlay IPs. |
| `routingMode: native` | No VXLAN/Geneve between nodes. The VPC router moves packets. |
| `ipv4NativeRoutingCIDR: <vpc cidr>` | Traffic whose destination is inside the VPC is **not** masqueraded. Other destinations are. |
| `egressMasqueradeInterfaces: ens5` | SNAT for internet egress uses the node’s **primary** ENI. AL2023 names that NIC `ens5`, not `eth0`. |
| `endpointRoutes.enabled: true` | Each pod IP gets a route on the node so Linux (and AWS source/dest checks) see the pod as on-link via the ENI. |
| `eni.nodeSpec.firstInterfaceIndex: 1` | **Never steal device index 0**. Index 0 is the primary ENI (node IP, default route, kubelet). Cilium starts attaching pod ENIs at index 1 (`ens6`, …). |
| `eni.subnetTagsFilter: kubernetes.io/role/internal-elb=1` | Pod ENIs are created only in **private /19** subnets. Public `/26`s and control-plane `/28`s are ignored. |
| `eni.awsEnablePrefixDelegation: true` | On Nitro instances, assign a `/28` prefix per ENI instead of individual IPs (higher pod density). |
| `kubeProxyReplacement: true` | Cilium programs Services in eBPF. kube-proxy must be gone. |
| `k8sServiceHost` / `k8sServicePort: 443` | Direct HTTPS to the EKS API FQDN. Required once kube-proxy (and therefore `kubernetes` ClusterIP) is gone. |
| `nodeinit.enabled: true` | Privileged DaemonSet that cleans leftover iptables/CNI state from `aws-node` / kube-proxy before the agent starts. |
| `operator.dnsPolicy: Default` | Operator uses the **node VPC DNS** (AmazonProvidedDNS at `.2`), not CoreDNS. CoreDNS cannot run until Cilium IPAM works. |
| `operator.replicas: 1` | Operator uses `hostNetwork`. Two replicas on a small node group collide on host ports during rolling updates. |
| Hubble + UI | Flow observability. UI is ClusterIP; reach it with `kubectl port-forward`. |

### What ENI mode looks like on a node

A `t3.medium` after a healthy install:

- **`ens5` (index 0)** — primary ENI. Node IP (e.g. `10.0.14.70`). Default
  route via the subnet router. kubelet, SSH/SSM, and NAT egress live here.
- **`ens6` (index 1)** — secondary ENI created by `cilium-operator`. Holds
  extra private IPs (or a `/28` prefix). **Those IPs are what pods get.**
- Cilium agent (hostNetwork) sits on the node IP and programs eBPF on
  `ens5`/`ens6` plus the veth pair of each pod (`lxc…`).

The pod does **not** get a `100.64.0.0/10` or overlay address. It gets
something like `10.0.5.195` from the same private subnet as the node
(or another private subnet in that AZ, depending on IPAM). From another
instance in the VPC, that IP is just another VPC address — security groups
and route tables apply as usual.

Prefix delegation (when EC2 honors it): instead of 6 secondary IPs on an
ENI, AWS attaches a `/28` (16 addresses) as a prefix. Cilium still hands
pods individual IPs from that prefix. If the instance or IAM path does not
allow prefixes, the operator falls back to classic secondary IPs
(`isPrefixDelegated=false` in logs). Networking still works.

---

## 4. Terraform pieces and apply order

Providers stay in the **root** (`eks-implementation/providers.tf`). Child
modules do not declare their own AWS/Helm providers. This module only
consumes Helm.

```
module.iam            → cluster + node IAM roles
module.cluster        → EKS API, KMS, OIDC, subnet cluster tags
module.nodegroup      → launch template (IMDS hop limit 2) + managed nodes
module.cilium_iam     → IRSA role <cluster>-cilium-operator
module.cilium         → 1) helm_release.disable_legacy_cni
                      → 2) helm_release.cilium   (depends_on 1)
```

`module.cilium` itself `depends_on` the node group and `cilium_iam`.
Until kubelet has registered at least one node, there is nowhere to
schedule the patch Job. Until the IRSA role exists, the operator cannot
call EC2.

Two Helm releases, not one, on purpose:

| Release | Chart | When Terraform considers it done |
|---|---|---|
| `disable-legacy-cni` | local, [`charts/disable-legacy-cni`](charts/disable-legacy-cni) | Hook Job succeeded **and** the leftover ConfigMap exists (`wait = true`, `atomic = true`, timeout 300s) |
| `cilium` | `https://helm.cilium.io/` version `var.chart_version` | Chart ready checks pass (`wait = true`, timeout 900s) |

`helm_release.cilium` has `depends_on = [helm_release.disable_legacy_cni]`.
Terraform will not even *start* the Cilium install if the patch release
failed or is still running. That is the sequencing guarantee: one
`terraform apply --auto-approve`, no pause, no human `kubectl`.

### Who talks to the API (and who does not)

There are **two** Kubernetes clients during apply. They must not be
confused:

1. **Helm provider (workstation / CI).** Authenticates with
   `aws eks get-token --cluster-name … --region …` via the provider
   `exec` block. It does **not** read `~/.kube/config`. A static
   `aws_eks_cluster_auth` token would expire in ~15 minutes; Cilium’s
   wait can exceed that, so exec refresh is mandatory. This client
   only *submits* Helm releases (Jobs, DaemonSets, Deployments).
2. **kubectl inside the hook Job (a worker node).** Authenticates with
   the in-cluster ServiceAccount token. It performs the actual
   `DaemonSet` PATCH. This is the client that replaces the old
   workstation `local-exec`.

`aws eks update-kubeconfig` remains an output of `eks-implementation`
for humans who want to debug. It is **not** an apply step.

---

## 5. Step A — Disable VPC CNI and kube-proxy (Terraform, in-cluster)

The cutover is the official Cilium patch: do **not** delete the
DaemonSets. Change their `nodeSelector` so they match **zero** nodes.

What the Job runs (equivalent `kubectl` for explanation only — Terraform
does not execute this on the laptop):

```bash
kubectl -n kube-system patch daemonset aws-node --type=strategic \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/aws-node-enabled":"true"}}}}}'

kubectl -n kube-system patch daemonset kube-proxy --type=strategic \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"io.cilium/kube-proxy-enabled":"true"}}}}}'
```

### 5.1 Why a nodeSelector that matches nothing

`io.cilium/aws-node-enabled=true` is **not** labelled on any node. After
the strategic-merge patch, the DaemonSet still exists, `desired` drops
to **0**, and Kubernetes terminates the running pods.

Why not `kubectl delete ds aws-node`?

- EKS (addon manager / default add-on reconciliation) can **recreate**
  `aws-node` and `kube-proxy`.
- A selector that never matches survives that recreate: the object comes
  back, still schedules on zero nodes.
- Deleting the object is a fight with EKS. Patching it is a truce.

After a successful patch:

```
kubectl -n kube-system get ds aws-node kube-proxy
# DESIRED 0  CURRENT 0  NODE SELECTOR  io.cilium/aws-node-enabled=true
# DESIRED 0  CURRENT 0  NODE SELECTOR  io.cilium/kube-proxy-enabled=true
```

Strategic merge on `nodeSelector` **adds** the new key. It does not
require removing `kubernetes.io/os=linux`. Both keys must match; our
key never does, so the pod template still schedules nowhere.

### 5.2 What actually dies on the node

When `aws-node` exits:

1. `aws-k8s-agent` / `ipamd` stop allocating IPs from the **primary** ENI.
2. The AWS CNI binary is no longer the active plugin for **new** pods.
   Existing sandboxes keep their old IPs until they are recreated.
3. Secondary IPs that VPC CNI already attached stay on the ENI until
   released. Cilium’s operator will later attach **its own** ENIs at
   index ≥ 1 rather than hijack index 0.

When `kube-proxy` exits:

1. iptables/IPVS Service rules are no longer maintained by kube-proxy.
2. ClusterIP access to `kubernetes.default` (and everything else) relies
   on Cilium. That is why `k8sServiceHost` must be the **real EKS API
   hostname**, not the in-cluster Service IP.
3. There is a short window where Services are broken for pods that still
   expected kube-proxy. Host-network Cilium can still reach the API
   because it uses the FQDN on 443, which is just VPC/public routing to
   the control plane ENIs.

The patch Job itself is hostNetwork and talks to the **FQDN**, so it
does not take that ClusterIP bullet. It finishes (or has already
finished) before Cilium starts.

### 5.3 Why this cannot be `local-exec` + laptop `kubectl`

The first *working* workaround was `terraform_data` +
`scripts/disable-legacy-cni.sh` on the machine that runs Terraform.
That is the opposite of what this stack is for:

- `terraform apply --auto-approve` is one graph. It cannot stop for
  `aws eks update-kubeconfig`.
- `local-exec` uses **whatever kubeconfig is current**. A recreate, a
  second AWS account, or a CI runner with no `kubectl` patches the
  wrong cluster — or nothing.
- Helm already has a correct, refreshable credential to *this* cluster.
  The patch must use that path, not a side channel.

So the patch is a **Helm release Terraform owns**, same provider, same
cluster endpoint, same exec authenticator as Cilium.

### 5.4 Second attempt: in-cluster Job (and why Bitnami blew up)

An in-cluster Job is the right shape: Kubernetes runs `kubectl patch`
after nodes exist, Terraform waits, then Cilium installs. The first
chart used `public.ecr.aws/bitnami/kubectl:1.35.0`. **That tag does not
exist.** The hook pod sat in `ImagePullBackOff`, Helm waited until
timeout, Terraform reported:

```
Helm release "disable-legacy-cni" was created but has a failed status
failed post-install: timed out waiting for the condition
```

`aws-node` / `kube-proxy` were never patched. Cilium then installed on
top of a live VPC CNI — two CNIs fighting over ENIs.

The image that **does** exist, and that AL2023 nodes can pull via NAT
from `registry.k8s.io`, is:

```
registry.k8s.io/kubectl:v1.35.0
```

Pinned as `var.kubectl_image`. It is the official distroless kubectl
image (multi-arch). Distroless means **no shell**, so the old bash
`if kubectl get; then patch; fi` script cannot run inside it. The chart
uses two sequential **initContainers** instead (section 5.6). Default
EKS clusters always create both DaemonSets; a missing object fails the
Job on purpose rather than silently skipping.

### 5.5 Helm chart layout and hook order

Chart path: [`charts/disable-legacy-cni`](charts/disable-legacy-cni).
Terraform sets values with `yamlencode` (no extra template file):

```hcl
kubectlImage  = var.kubectl_image          # registry.k8s.io/kubectl:v1.35.0
apiServerHost = local.k8s_service_host     # EKS API FQDN, https:// stripped
apiServerPort = "443"
```

Helm 3 treats any rendered manifest with `helm.sh/hook` as a **hook**:
it runs those objects first, waits for Jobs, then installs regular
resources. Weights are strings; lower runs first:

| Weight | Objects | Role |
|---|---|---|
| `-20` | ServiceAccount, Role, RoleBinding | Identity the Job will use |
| `-10` | Job `disable-legacy-cni` | PATCH the two DaemonSets |
| (none) | ConfigMap `disable-legacy-cni` | Regular resource so the release is not “hooks only” |

Hook annotations on SA/Role/Job:

```
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

Meaning:

- **pre-install** — first `terraform apply` on a new cluster.
- **pre-upgrade** — later apply that changes the chart or image: patch
  again before Helm moves on.
- **before-hook-creation** — delete the previous hook Job so a retry
  does not hit an immutable Job spec.
- **hook-succeeded** — delete the Job after success so `kube-system`
  is not littered with Completed pods. A **failed** Job is kept so the
  logs are still there.

`atomic = true` and `cleanup_on_fail = true` on the Terraform resource:
if the hook fails, Helm uninstalls this release instead of leaving a
half-created `failed` release (that was the Bitnami failure mode).
Cilium never starts (`depends_on`).

The ConfigMap is *not* a hook. Helm waits for it after the Job
succeeds. A chart that is only hooks can confuse `helm wait`; the
ConfigMap is a durable, empty-of-logic marker that the cutover chart
is installed. It records the two selector keys for operators reading
the cluster.

### 5.6 How the Job is scheduled (it must not need CNI)

At this moment in the apply, **VPC CNI is still the CNI**. The Job
could take a pod IP from `aws-node`. It does **not**, by design:

| Field | Why |
|---|---|
| `hostNetwork: true` | Uses the node IP. No CNI ADD. Survives the instant `aws-node` pods are killed. |
| `dnsPolicy: Default` | Node `/etc/resolv.conf` → AmazonProvidedDNS. `kubernetes.default.svc` would **not** resolve. |
| `KUBERNETES_SERVICE_HOST=<EKS FQDN>` | Overrides the injected ClusterIP. kubectl talks to the API the same way Cilium will after kube-proxy is gone. In-cluster CA + SA token still apply; the EKS API cert matches that FQDN. |
| `KUBERNETES_SERVICE_PORT=443` | Matches the API listener. |
| `tolerations: Exists` | Schedules even if the node is briefly NotReady or has startup taints. |
| `serviceAccountName: disable-legacy-cni` | RBAC below. |
| `backoffLimit: 4` | Image pull or a slow API can retry. |
| `activeDeadlineSeconds: 180` | Hard cap; Terraform’s Helm timeout is 300s. |
| `runAsUser: 65532` | Distroless nonroot. kubectl does not need root. |

The node pulls `registry.k8s.io` through the **private subnet NAT**.
If NAT is missing, this Job (and later Cilium images) cannot start.
That is a bootstrap-stack problem, not a Cilium problem.

### 5.7 RBAC: least privilege, named objects

The Role is namespaced to `kube-system` and limited to two names:

```
apiGroups: ["apps"]
resources: ["daemonsets"]
resourceNames: ["aws-node", "kube-proxy"]
verbs: ["get", "patch"]
```

`kubectl patch` GETs the object then sends a PATCH. No `create`, no
`delete`, no other DaemonSets. The RoleBinding binds that Role to
`disable-legacy-cni`. All three objects are hooks at weight `-20`, so
they exist before the Job at `-10`.

### 5.8 Distroless initContainers (the actual PATCH)

Entry point of the image is `/kubectl`. Kubernetes `args` become kubectl
arguments. There is no `sh`.

1. **initContainer `patch-aws-node`** — `kubectl patch daemonset aws-node …`
2. **initContainer `patch-kube-proxy`** — same for `kube-proxy`
3. **container `complete`** — `kubectl version --client` (does not need
   the API). A Job must have a main container; this one exists only to
   exit 0 after both inits succeeded.

Init containers are **sequential**. kube-proxy is still running while
`aws-node` is patched. By the time kube-proxy is patched, the Job has
already finished talking to the API via the FQDN, not via kube-proxy.

The same PATCH applied twice is a no-op success (idempotent). Re-running
the hook on upgrade does not flap the DaemonSets.

### 5.9 Timeline of one `terraform apply` (new cluster)

Assume bootstrap VPC is already up. The human runs only:

```bash
cd eks-implementation
terraform apply --auto-approve
```

What happens, in order Terraform can actually wait on:

1. **IAM + EKS control plane + OIDC.** Minutes. Default add-ons
   (`aws-node`, `kube-proxy`, CoreDNS) appear in `kube-system`.
2. **Managed node group.** Nodes join. `aws-node` writes
   `/etc/cni/net.d/`. Nodes become Ready. CoreDNS may go Running
   briefly on VPC CNI IPs — that is expected and temporary.
3. **`cilium_iam`.** IRSA role for the operator. No pods yet.
4. **`helm_release.disable_legacy_cni`.**
   - Helm (workstation) calls the EKS API with a fresh `get-token`.
   - Hook weight `-20`: SA / Role / RoleBinding.
   - Hook weight `-10`: Job scheduled on a node (hostNetwork).
   - Node pulls `registry.k8s.io/kubectl:v1.35.0` via NAT.
   - Init 1 PATCHes `aws-node` → replica pods terminate → `desired=0`.
   - Init 2 PATCHes `kube-proxy` → same.
   - Main container exits 0. Helm marks the hook succeeded and deletes
     the Job (`hook-succeeded`).
   - ConfigMap is created. Helm `wait` returns. Terraform marks this
     resource created.
5. **`helm_release.cilium`** starts only now (`depends_on`).
   node-init, operator, agents, Hubble. See section 6.
6. Operator attaches secondary ENIs. Agents become Ready. CoreDNS and
   Hubble get Cilium IPs.

Failure in step 4 (`ImagePullBackOff`, RBAC, missing DaemonSet, timeout)
fails the Helm release, `atomic` rolls it back, and step 5 never runs.
You do not get a hybrid CNI.

### 5.10 Later applies (idempotency)

- **No chart/image change:** Helm sees the release, no upgrade, hook
  does not run. DaemonSets stay parked. Cilium is unchanged.
- **Chart or `kubectl_image` change:** Helm upgrade → `pre-upgrade`
  hook runs the Job again → same PATCH → success → ConfigMap in place.
- **Someone manually un-parks `aws-node`:** a no-op apply will **not**
  notice (Helm has nothing to change). The next chart/image bump, or a
  `terraform taint 'module.cilium.helm_release.disable_legacy_cni'`
  (or equivalent replace), re-runs the hook. The durable protection
  remains the nodeSelector: EKS recreating the DaemonSet still comes
  back with that selector if the last apply of the object kept it;
  a full EKS addon reset is the case that needs the hook again.

This is still one Terraform graph. It is not two stacks and not a
manual gate.

---

## 6. Step B — Helm installs Cilium

This release does not start until `helm_release.disable_legacy_cni` is
`deployed` (section 5.9). `aws-node` and `kube-proxy` are already
`desired=0`.

`helm_release.cilium` waits until the chart’s own ready checks pass
(`wait = true`). Chart source: `https://helm.cilium.io/`, version from
`var.chart_version` (currently `1.20.1`).

Components in `kube-system`:

| Workload | Network | Role |
|---|---|---|
| `cilium-node-init` (DS) | hostNetwork | One-shot cleanup: leftover AWS CNI files, kube-proxy iptables, BPF mounts. |
| `cilium` (DS) | hostNetwork | Agent: CNI plugin, eBPF datapath, kube-proxy replacement, endpoint IPAM consumer. |
| `cilium-envoy` (DS) | hostNetwork | L7 proxy used by Hubble / L7 policy. |
| `cilium-operator` (Deployment) | hostNetwork | Leader-elected. Talks to **EC2**. Owns ENI IPAM and `CiliumNode` CRs. |
| `hubble-relay` / `hubble-ui` | **pod network** | Need a working CNI. Stay `Pending`/`ContainerCreating` until agents are Ready. |
| CoreDNS (EKS default) | **pod network** | Same: cannot schedule until agents allocate IPs. |

Helm “deployed” is **not** the same as a healthy datapath. The chart can
become `deployed` while agents are still `CrashLoopBackOff` waiting for
the operator’s CIDR pool. Always confirm with `kubectl` (section 11).

---

## 7. Under the hood — operator, IRSA, IMDS, IPAM

### 7.1 Identity (IRSA)

[`../cilium-iam`](../cilium-iam) creates
`arn:aws:iam::<account>:role/<cluster>-cilium-operator`.

Trust: only the OIDC provider of *this* cluster, only
`system:serviceaccount:kube-system:cilium-operator`.

The Helm values set two things that must agree:

- `serviceAccounts.operator.annotations.eks.amazonaws.com/role-arn`
- `eni.iamRole` (tells the chart not to expect static AWS keys)

EKS injects into the operator pod:

- `AWS_ROLE_ARN`
- `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`

The AWS SDK calls `sts:AssumeRoleWithWebIdentity` (and `sts:TagSession`).
No access keys live in the cluster.

Permissions are split:

- **Describe\*** on `*` — EC2 describe APIs cannot be resource-scoped.
- **Create/Attach/Assign/…** only when `aws:RequestedRegion` is this
  region — the operator may mutate ENIs here, not in another region.

### 7.2 IMDS is mandatory

The operator still reads the **instance identity document** from the
node IMDS (`169.254.169.254`) to know *which* instance it is running on
and to initialize ENI instance-type limits.

The node launch template sets:

```
http_endpoint               = enabled
http_tokens                 = required     # IMDSv2 only
http_put_response_hop_limit = 2            # pods can reach IMDS
```

Do **not** set `AWS_EC2_METADATA_DISABLED=true` on the operator. That
workaround was tried when EC2 API calls timed out (CoreDNS chicken-egg).
The process then crashed with:

```
unable to retrieve instance identity document: access disabled to EC2 IMDS
```

The real fix for “operator cannot resolve/reach AWS APIs while CoreDNS
is down” is `dnsPolicy: Default`, not disabling IMDS.

### 7.3 IPAM loop (this is the replacement of `ipamd`)

Once the operator is leader:

1. Installs Cilium CRDs (`CiliumNode`, `CiliumEndpoint`, `CiliumCIDRGroup`, …).
2. Calls EC2: instance types, ENI limits, subnets, route tables, SGs.
   Log line to look for:
   `Initial EC2 API limits update completed successfully`
3. Watches `CiliumNode` objects (one per Kubernetes node). The **agent**
   creates/updates the local `CiliumNode`.
4. If the node has fewer free IPs than the pre-allocation watermark:
   - Prefer unused IPs on an existing secondary ENI.
   - Else `CreateNetworkInterface` in a subnet that matches
     `subnetTagsFilter` **and** the node’s AZ.
   - `AttachNetworkInterface` at the next index ≥ `firstInterfaceIndex`.
5. Writes the allocated IPs onto `CiliumNode.status`. That is the **CIDR
   pool** the agent was waiting for.

Agent log while the pool is empty:

```
Waiting for cidr pool to become available  poolName=default  family=ipv4
```

That message is normal for a few seconds. It is fatal only if the
operator cannot talk to EC2 (IAM, IMDS, DNS, or network).

When a pod starts, kubelet invokes the Cilium CNI plugin. The **agent**
picks a free IP from *its* node’s pool, programs the veth + BPF, and
updates `CiliumEndpoint`. The operator is not in the hot path of every
pod create; it only keeps the pool topped up.

### 7.4 Security groups on pod ENIs

New ENIs inherit the **cluster security group** (the one EKS attaches to
nodes) unless you add an explicit `eni.securityGroups` list. Pod-to-pod
and pod-to-control-plane traffic therefore follows the same SG as the
nodes, plus whatever Cilium NetworkPolicy you add later.

---

## 8. Under the hood — agent, CNI binary, kube-proxy replacement

### 8.1 Node-init then agent

`cilium-node-init` runs first (privileged). It removes stale AWS CNI
configuration so kubelet does not keep calling `aws-cni`. Then the agent:

1. Mounts BPF fs, loads programs (`cil_from_netdev`, `cil_to_netdev` on
   `ens5`/`ens6`, `cil_from_container` on each pod veth).
2. Writes Cilium’s CNI config into `/etc/cni/net.d/` (typically a file
   with a name that sorts **before** leftovers, e.g. `05-cilium.conflist`).
3. Waits for Kubernetes informers (including `CiliumCIDRGroup`). If the
   CRDs are not there yet, the agent can hit a 3 minute timeout:
   `never received event for resource "cilium/v2::CiliumCIDRGroup"`
   Restarting agents *after* the operator is healthy recovers this; it
   is a race on first boot, not a permanent misconfig.
4. Takes IPs from the `CiliumNode` pool and starts answering CNI ADD.

kubelet Ready was already true (nodes use the primary ENI). **Pod**
Ready is what flips here: CoreDNS leaves `Pending`, Hubble leaves
`ContainerCreating`.

### 8.2 kube-proxy replacement

With `kubeProxyReplacement: true`:

- ClusterIP / NodePort / LoadBalancer (with externalTrafficPolicy) are
  implemented as BPF socket-level or XDP/tc LB, not iptables DNAT chains.
- Cilium must know how to reach the API **before** that BPF Service map
  exists. Hence `k8sServiceHost=<api-id>.gr7.<region>.eks.amazonaws.com`
  (the module strips `https://` from `cluster_endpoint`).
- Nodes talking to the API use the VPC path to control-plane ENIs (or
  the public endpoint, depending on `endpoint_private_access` /
  `endpoint_public_access`). That path never needed kube-proxy.

---

## 9. CoreDNS, Hubble, and the DNS chicken-egg

| Consumer | Needs pod network? | Needs CoreDNS? |
|---|---|---|
| Cilium agent | No (hostNetwork) | No (`k8sServiceHost` is a FQDN; node resolver is VPC DNS) |
| Cilium operator | No (hostNetwork) | **Must not**: `dnsPolicy: Default` → `/etc/resolv.conf` of the node → `AmazonProvidedDNS` |
| CoreDNS itself | **Yes** | No (it *is* DNS) |
| Hubble UI / Relay | **Yes** | Only for in-cluster names; not needed to *start* |
| Application pods | Yes | Yes, once CoreDNS is Ready |

If the operator used the default `ClusterFirst` policy, it would try to
reach `ec2.<region>.amazonaws.com` through `kube-dns` ClusterIP. That
Service has no backends until CoreDNS runs, CoreDNS has no IP until ENI
IPAM works, IPAM does not work until the operator reaches EC2. Deadlock.

`dnsPolicy: Default` breaks that cycle. After CoreDNS is up you *could*
switch the operator to ClusterFirst; it is unnecessary — VPC DNS is the
correct resolver for AWS API hostnames anyway.

---

## 10. How this depends on the VPC (bootstrap stack)

ENI mode is only as correct as the subnet plan in
`bootstrap-infrastructure/locals.tf`:

| Subnet | Tag Cilium cares about | Used for |
|---|---|---|
| Private `/19` × 3 AZs | `kubernetes.io/role/internal-elb=1` | Nodes **and** pod ENIs |
| Public `/26` | `kubernetes.io/role/elb=1` only | NAT, internet-facing LBs — **not** pod ENIs |
| Control-plane `/28` | neither elb tag | EKS-managed API ENIs only |

`ipv4NativeRoutingCIDR` is the whole VPC CIDR (e.g. `10.0.0.0/16`). If
you ever add extra RFC1918 ranges (peering, TGW), traffic to those
destinations will be masqueraded unless you widen this CIDR (or add
routes/policies). That is a design choice, not a bug.

Nodes are launched **only** in private subnets. Pod ENIs follow the
node’s AZ: an instance in `us-east-1a` gets a secondary ENI in the
private subnet of `us-east-1a`. Cross-AZ ENI attach is not a thing.

---

## 11. How to verify (after apply or after a recreate)

```bash
# Helm releases Terraform owns (no kubeconfig was required to create them)
helm status disable-legacy-cni -n kube-system
helm status cilium -n kube-system

# Defaults are parked
kubectl -n kube-system get ds aws-node kube-proxy
# desired = 0
# ConfigMap left by the cutover chart
kubectl -n kube-system get configmap disable-legacy-cni

# Datapath
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system get pods -l io.cilium/app=operator
kubectl -n kube-system exec ds/cilium -- cilium status
# expect OK

# Workloads that need CNI
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system get pods -l k8s-app=hubble-relay
kubectl -n kube-system get pods -l k8s-app=hubble-ui

# Operator actually created ENIs
kubectl get ciliumnodes
# status should list eni-… at index 1+

# Hubble UI (ClusterIP)
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
```

Operator logs that mean IPAM is alive:

```
Starting ENI allocator...
Initial EC2 API limits update completed successfully
Created new ENI ... index=1
Attached ENI to instance
```

---

## 12. Recreating the cluster (reproducibility)

Destroying `eks-implementation` and applying again is the intended test.
Expected order on a clean account/VPC (bootstrap already applied):

1. IAM roles for cluster + nodes.
2. EKS control plane + OIDC.
3. Nodes join with stock `aws-node` + `kube-proxy` (minutes).
4. IRSA role for the operator.
5. Helm `disable-legacy-cni` (section 5.9): hook Job on a node PATCHes
   both DaemonSets; Terraform waits; Cilium has not started yet.
6. Helm Cilium → node-init, operator, agents.
7. Operator attaches ENIs; agents become 1/1; CoreDNS/Hubble start.

The only credentials on the machine running apply are AWS credentials
with permission to call `eks:GetToken` (and to manage the rest of the
stack). `kubectl` on that machine is optional.

If agents crash with “waiting for cidr pool”, read operator logs first
(IAM / IMDS / DNS), not agent logs.

Terraform state for this stack is independent from bootstrap (VPC). A
cluster destroy does **not** destroy subnets, NAT, or the S3 backend.
A second account needs: bootstrap applied there, `terraform.tfvars`
pointing at that backend, and AWS credentials for that account.

---

## 13. Lessons baked into the values (do not “simplify” blindly)

These existed as real failures, not style choices:

1. **Pin a kubectl image that exists** — `registry.k8s.io/kubectl:v1.35.0`,
   not `public.ecr.aws/bitnami/kubectl:1.35.0`. Run it `hostNetwork` and
   aimed at the EKS API FQDN. Do not patch from the workstation.
2. **Never disable IMDS** on the operator — ENI mode needs the instance
   identity document.
3. **`dnsPolicy: Default`** — CoreDNS is down during the cutover.
4. **`ens5` not `eth0`** — AL2023 EKS AMI.
5. **`firstInterfaceIndex: 1`** — protecting the primary ENI is the
   difference between “pods get IPs” and “the node loses its default
   route”.
6. **`k8sServiceHost` = EKS FQDN** — kube-proxy is gone.
7. **One operator replica** on small node groups — `hostNetwork` port
   conflicts during rolling updates (`replicas: 2` failed scheduling).
8. **Helm wait can lie** — confirm DaemonSets and `cilium status`.

---

## 14. What this module does not do

- It does not manage the VPC, cluster, or node group (other modules).
- It does not uninstall EKS default add-on *objects*; it parks them with
  a nodeSelector.
- It does not install the AWS Load Balancer Controller, cluster
  autoscaler, ESO, or Istio.
- Hubble UI is not exposed publicly.
- Prometheus `ServiceMonitor` is off until a Prometheus Operator exists.
- IAM for the **node** role still includes `AmazonEKS_CNI_Policy` from
  the generic node module. Cilium ENI mutations are done by the
  **operator** role, not by that policy. Leaving the managed policy on
  nodes is harmless leftover from the stock EKS node recipe; it is not
  what drives this CNI.
