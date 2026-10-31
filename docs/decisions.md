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
- A device that trusts the CA accepts whatever it signs, and its key is a Secret in the cluster, so cluster-admin access would mean certificates for any website. The CA therefore carries X.509 name constraints: `home.arpa` only, no IP addresses. Clients enforce them, not cert-manager (tested with OpenSSL and the macOS verifier: `dashboard.home.arpa` passes, `github.com` and an IP address are rejected). It needs the `NameConstraints` feature gate, which is alpha in cert-manager 1.21.
- The CA's private key lives only in the cluster, so a rebuild creates a new CA that has to be trusted again. Keeping it encrypted in Git waits for SOPS and age, like the Flux deploy key.
- Flux does not verify the chart's signature: cert-manager documents cosign for its images and GPG for its classic Helm repository, but not how the OCI chart is signed.

## 6. Traefik (bundled with K3s), not ingress-nginx

The Kubernetes project retired ingress-nginx in March 2026, so it receives no security fixes. K3s bundles Traefik, which is maintained and also supports Gateway API. Apps use standard `Ingress` objects for now, with TLS from the `homelab-ca` issuer.

From the Mac, Lima forwards ports 80 and 443 to Traefik. macOS lets a normal user bind ports below 1024 only on the wildcard address, so Lima listens on all interfaces but closes every connection that does not come from the Mac itself (its "pseudoloopback" forwarder): the apps answer on `https://<name>.home.arpa` from the Mac, and devices on the LAN get their connection closed.

**Next step:** move to Gateway API once the basics work.

## 7. A dashboard (Homepage) as the first app

The first app is [Homepage](https://gethomepage.dev), a start page for the homelab, rather than a monitoring tool such as Uptime Kuma. It is stateless (its configuration is a ConfigMap generated from `apps/base/homepage/config/`), so it needs no persistent volume or backup, and it exercises the whole path: Flux, Ingress, cert-manager TLS and a NetworkPolicy. New apps add themselves to the dashboard with `gethomepage.dev/*` annotations on their Ingress, so the dashboard grows without editing its config.

It is deployed with plain manifests written here, following the upstream Kubernetes guide: the only Helm chart is unofficial and installs Homepage v1. The image is pinned to v2.6.0, one minor behind the newest; versions 2.0.0 to 2.5.0 are affected by a high-severity advisory (GHSA-qxcr-4rv3-v23r) fixed in 2.6.0.

**Trade-offs:**

- Homepage gets a read-only ClusterRole (nodes, pods, namespaces, ingresses and metrics) to show node usage and discover apps. It cannot read Secrets, Traefik IngressRoutes or Gateway API routes; discovery of those is turned off in `kubernetes.yaml`.
- Homepage's login gate (`HOMEPAGE_AUTH_ENABLED`) is off, because its password and cookie secret would be the first secrets in the repository and SOPS is not set up yet. The dashboard is only reachable from the Mac mini (decision 6); turn the login on before exposing it to the LAN.
- Uptime-style monitoring moves to the "Lightweight monitoring" roadmap item.
