# Design decisions

Short records of the choices behind this repository and the trade-offs I accepted.

## 1. Lima VMs on a Mac mini

Kubernetes needs Linux, and I wanted a real multi-node cluster (not containers pretending to be nodes), with each node a full operating system. [Lima](https://lima-vm.io) runs arm64 Ubuntu VMs natively on Apple Silicon and connects them with its `user-v2` network, which was designed for multi-node Kubernetes.

**Trade-off:** one physical machine, so no real high availability. The three nodes teach scheduling and failure handling but do not survive hardware failure.

## 2. K3s, pinned one minor version behind the newest

K3s is lightweight, ships with arm64 builds and fits in 16 GB of RAM next to three VMs. The version is pinned in `ansible/inventory/group_vars/k3s_cluster.yml` and sits one minor release behind the newest line, which has had more time to collect patches. Upgrading means changing that one value and re-running the playbook.

## 3. Ansible provisions the nodes, Lima only creates them

Lima templates can install K3s on their own, which is quicker. I kept Lima to "create plain Ubuntu VMs" so the same playbooks can later run unchanged on a mini PC or a VPS. The workers join with an agent-only token, which the server generates and the playbook reads at run time; it is never stored in Git, and unlike the server token it cannot be used to take over the cluster.

**Trade-off:** more code than a Lima template, and I have to maintain the install logic myself.

## 4. Flux for GitOps, installed through a pull request

Flux reconciles the cluster from this repository. `clusters/homelab/` is its entry point, and Flux's own manifests sit in `clusters/homelab/flux-system/`, so Flux also manages its own installation: upgrading it is a pull request like any other change.

I did not use `flux bootstrap`. It needs a personal access token that can push to the repository and manage its deploy keys, and it pushes its commit straight to `main`, which the branch ruleset rejects (every change goes through a pull request and the `Lint` check). Instead I generated the same manifests with the Flux CLI, merged them through a pull request, and created the SSH key inside the cluster. GitHub only holds the public half, as a deploy key without write access: Flux can read this one repository and cannot push to it.

**Trade-offs:**

- The first install is a few manual commands instead of one (they are in the README).
- The private key lives only in the cluster, so a rebuild needs a new deploy key. Keeping it encrypted in Git waits for SOPS and age (roadmap).
- Flux is pinned to v2.10.0, the newest release, an exception to the "one minor behind" rule of decision 2. The Flux CLI only generates manifests for its own version (v2.10.0 refused to generate v2.9.6), and the CLI and the controllers should match, so following the rule would mean keeping an older CLI around. Flux v2.10.0 needs Kubernetes 1.35 or newer; the cluster runs 1.36.

## 5. cert-manager with an internal CA, and the `home.arpa` domain

Apps get TLS certificates from [cert-manager](https://cert-manager.io), which issues them from Kubernetes objects and renews them before they expire. They are signed by a CA created inside the cluster: a self-signed issuer signs the `homelab-ca` certificate, and the `homelab-ca` ClusterIssuer signs the apps' certificates. The apps will use `home.arpa`, the domain reserved for home networks (RFC 8375); `.local` belongs to mDNS and `.lan` is not reserved at all. No public CA can issue certificates for `home.arpa`, hence the internal one.

Flux installs cert-manager from its official Helm chart (OCI, on quay.io) in two steps: `infrastructure/controllers` installs the chart and its CRDs, then `infrastructure/configs` creates the issuers, which need those CRDs (`dependsOn`). The chart is pinned to v1.21.3, the newest minor rather than one behind: cert-manager 1.20 does not support Kubernetes 1.36. So the rule of decision 2 reads: one minor behind, unless that minor does not support the cluster's Kubernetes version.

**Trade-offs:**

- Browsers distrust the CA until its certificate is installed on each device. A real domain with DNS-01 validation would remove that, at the cost of owning a domain; on a VPS, only the issuer would change.
- The CA's private key lives only in the cluster, so a rebuild creates a new CA that has to be trusted again. Keeping it encrypted in Git waits for SOPS and age, like the Flux deploy key.
- Flux does not verify the chart's signature: cert-manager documents cosign for its images and GPG for its classic Helm repository, but not how the OCI chart is signed.
