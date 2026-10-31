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

Each VM runs Ubuntu 26.04 with 2 vCPUs, 2 GiB of RAM and a 20 GiB disk that only takes the space it uses. The VMs share Lima's `user-v2` network, so they reach each other by name (`lima-homelab-cp.internal`). The kubeconfig is written to `~/.kube/homelab.yaml`, outside the repository because it holds the cluster admin credentials, and reaches the API through Lima's port forward on `127.0.0.1:6443`. It is overwritten on every run; to use another file, pass an absolute path, for example `make up KUBECONFIG_FILE=$HOME/.kube/my-lab.yaml` (and the same to `make kubeconfig`). A missing folder is created readable only by you (0700); an existing folder is left as it is.

Connecting with kubectl: kubectl reads `~/.kube/config` unless the `KUBECONFIG` variable names another file, so each new terminal needs pointing at this one:

```bash
eval "$(make -s kubeconfig)"                          # from the repo folder (make only prints the export line)
export KUBECONFIG=~/.kube/homelab.yaml                # the same, from any folder
kubectl --kubeconfig ~/.kube/homelab.yaml get nodes   # a single command, nothing exported
kubectl config get-contexts                           # check: the current context (*) is homelab
```

To make it permanent, append the `export` line to your shell's profile. Run only the line for your shell (`echo $SHELL` tells you which), once, then open a new terminal:

```bash
printf '\nexport KUBECONFIG=$HOME/.kube/homelab.yaml\n' >> ~/.zshrc         # zsh, the macOS default
printf '\nexport KUBECONFIG=$HOME/.kube/homelab.yaml\n' >> ~/.bash_profile  # bash
```

`>>` appends to the file (a single `>` would replace the whole profile), and the leading `\n` keeps the new line separate even when the profile does not end with a newline. With bash, if your settings live in `~/.profile` and there is no `~/.bash_profile`, append to `~/.profile` instead: bash reads only the first of the two it finds, so creating `~/.bash_profile` would stop `~/.profile` from loading. Every new terminal then talks to this cluster; to undo it, delete that line from the profile.

After `make down` and `make up` the cluster has a new certificate authority: the kubeconfig is rewritten, but copies of it (for example one loaded into a desktop app) stop working until they are loaded again.

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
