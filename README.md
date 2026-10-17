# homelab

A three-node Kubernetes cluster on a Mac mini (M4, 16 GB), built entirely from code and managed with GitOps.

> **Status: just started.** This repository grows one stage at a time, and each stage is committed once it actually runs on the Mac mini. The roadmap below is ticked only for things that work.

## The plan

| Layer | Tool | Role |
| --- | --- | --- |
| Virtual machines | [Lima](https://lima-vm.io) | Three plain Ubuntu arm64 VMs that can reach each other |
| Provisioning | [Ansible](https://docs.ansible.com) | Installs and configures K3s on the VMs |
| Kubernetes | [K3s](https://k3s.io) | One control plane and two workers |
| GitOps | [Flux](https://fluxcd.io) | Reconciles the cluster from this repository |
| TLS | [cert-manager](https://cert-manager.io) | Internal certificate authority for the apps |
| First app | [Homepage](https://gethomepage.dev) | A dashboard for the homelab |

## Roadmap

- [ ] Three Lima VMs created with one command
- [ ] CI: lint and validate every push
- [ ] K3s installed on them with Ansible
- [ ] Flux bootstrapped and syncing this repository
- [ ] cert-manager and the internal CA
- [ ] Homepage dashboard
- [ ] Reach the apps from the LAN
- [ ] Pi-hole
- [ ] Secrets with SOPS and age
- [ ] Backups of the persistent volumes
- [ ] Lightweight monitoring
- [ ] Gateway API instead of Ingress
- [ ] A kubeadm-based Kubernetes cluster built the same way, to compare with K3s

## Usage

Everything runs through the Makefile. `make help` lists the available targets.

## License

MIT
