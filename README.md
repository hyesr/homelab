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

- [x] Three Lima VMs created with one command
- [x] CI: lint every push
- [ ] K3s installed on them with Ansible
- [ ] Flux bootstrapped and syncing this repository
- [ ] CI: validate the Kubernetes manifests
- [ ] cert-manager and the internal CA
- [ ] Homepage dashboard
- [ ] Reach the apps from the LAN
- [ ] Pi-hole
- [ ] Secrets with SOPS and age
- [ ] Backups of the persistent volumes
- [ ] Lightweight monitoring
- [ ] Gateway API instead of Ingress
- [ ] A kubeadm-based Kubernetes cluster built the same way, to compare with K3s

## Getting started

Requirements: macOS on Apple Silicon with [Lima](https://lima-vm.io) 2.0 or newer (`brew install lima`).

```bash
make vms       # create the three VMs (or start them if they exist)
make status    # list them
make stop      # stop them, keeping their state
make start     # start them again
make down      # delete them
```

Each VM runs Ubuntu 26.04 with 2 vCPUs, 2 GiB of RAM and a 20 GiB disk that only takes the space it uses. The VMs share Lima's `user-v2` network, so they reach each other by name (`lima-homelab-cp.internal`). `make help` lists every target.

## Development

Every pull request runs `make lint` in GitHub Actions. Run the same checks locally before pushing:

```bash
brew install shellcheck
python3.14 -m venv .venv          # yamllint needs Python 3.10 or newer; macOS's python3 is 3.9
source .venv/bin/activate
pip install -r requirements-dev.txt
make lint                         # yamllint and shellcheck; no output means no problems
```

## License

MIT
