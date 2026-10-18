# homelab

A three-node Kubernetes cluster on a Mac mini (M4, 16 GB), built entirely from code and managed with GitOps.

> **Status: early stage.** The VMs, CI and the K3s cluster work; GitOps with Flux is next. This repository grows one stage at a time, and each stage is committed once it actually runs on the Mac mini. The roadmap below is ticked only for things that work.

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
- [x] K3s installed on them with Ansible
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

Requirements: macOS on Apple Silicon with [Lima](https://lima-vm.io) 2.0 or newer and kubectl (`brew install lima kubectl`), plus the Python tools from [Development](#development) (Ansible runs from that virtual environment).

```bash
source .venv/bin/activate        # the Ansible virtual environment (see Development)
make up                          # create the three VMs and install K3s on them with Ansible
eval "$(make -s kubeconfig)"     # point kubectl at the cluster (this terminal only)
kubectl get nodes                # one control plane and two workers, all Ready
```

Each VM runs Ubuntu 26.04 with 2 vCPUs, 2 GiB of RAM and a 20 GiB disk that only takes the space it uses. The VMs share Lima's `user-v2` network, so they reach each other by name (`lima-homelab-cp.internal`). The kubeconfig is written to `.kube/homelab.yaml` (git-ignored) and reaches the API through Lima's port forward on `127.0.0.1:6443`.

Day to day:

```bash
make up          # safe to re-run: starts stopped VMs and re-applies the playbook (no changes if all is well)
make stop        # stop the VMs, keeping their state
make start       # start them again (VMs only, no playbook)
make status      # list the VMs
make ping        # check that Ansible reaches every node
make provision   # re-run the playbook; a second run reports no changes
make down        # delete the VMs and the cluster
```

**Upgrading K3s:** change `k3s_version` and `k3s_install_script_checksum` (the command to get it is in the file) in `ansible/inventory/group_vars/k3s_cluster.yml`, and run `make provision`. The playbook upgrades the server first, then the workers one at a time (not yet exercised with a real upgrade). `make help` lists every target.

## Development

Ansible and the linters are pinned in `requirements-dev.txt` and installed in a virtual environment, the same versions CI uses. Every pull request runs `make lint` in GitHub Actions; run the same checks locally before pushing:

```bash
brew install shellcheck
python3.14 -m venv .venv          # ansible-core needs Python 3.12 or newer; macOS's python3 is 3.9
source .venv/bin/activate         # needed in every new terminal
pip install -r requirements-dev.txt
make lint                         # yamllint, ansible-lint (production profile) and shellcheck
```

## License

MIT
