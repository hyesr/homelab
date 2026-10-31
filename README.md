# homelab

A three-node Kubernetes cluster on a Mac mini (M4, 16 GB), built entirely from code and managed with GitOps.

> **Status: early stage.** The VMs, CI, the K3s cluster, GitOps with Flux, the internal CA and the first app (a dashboard) work. This repository grows one stage at a time, and each stage is committed once it actually runs on the Mac mini. The roadmap below is ticked only for things that work.

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
- [x] Flux installed and syncing this repository
- [x] CI: validate the Kubernetes manifests
- [x] cert-manager and the internal CA
- [x] Homepage dashboard
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

## GitOps with Flux

[Flux](https://fluxcd.io) v2.10.0 runs in the cluster and keeps it in step with `main`: it fetches the repository every minute and applies what is under `clusters/homelab/` whenever `main` changes (and every 10 minutes anyway). With `prune: true`, what is removed from Git is removed from the cluster too. Flux's own manifests are in `clusters/homelab/flux-system/`, so Flux manages its own installation as well.

It was installed without `flux bootstrap`, which pushes straight to `main` (see [decision 4](docs/decisions.md#4-flux-for-gitops-installed-through-a-pull-request)). On a fresh cluster, with the Flux CLI installed (`brew install fluxcd/tap/flux`, the same version as the manifests):

```bash
flux check --pre                                                                  # the cluster meets Flux's requirements
kubectl apply --server-side -f clusters/homelab/flux-system/gotk-components.yaml  # the controllers and their CRDs
flux check                                                                        # the controllers are ready
flux create secret git flux-system --url=ssh://git@github.com/hyesr/homelab       # an SSH key pair; prints the public key
```

Add the printed public key in the repository's **Settings → Deploy keys**, with **Allow write access** unchecked. Then:

```bash
kubectl apply --server-side -f clusters/homelab/flux-system/gotk-sync.yaml        # "fetch main, apply clusters/homelab"
flux get sources git                                                              # flux-system: Ready, at main's latest commit
flux get kustomizations                                                           # flux-system: Ready, same commit
```

The private key exists only in the cluster, so `make down` loses it: after a rebuild, create a new one and delete the old deploy key on GitHub. From a fork, change `url` in `gotk-sync.yaml` and the `--url` above to your repository.

**Upgrading Flux:** regenerate the components with the new CLI (`flux install --export > clusters/homelab/flux-system/gotk-components.yaml`) and merge it through a pull request; Flux applies its own upgrade (not yet exercised with a real upgrade).

## The dashboard

Flux deploys [Homepage](https://gethomepage.dev) at `https://dashboard.home.arpa`, behind Traefik, with a certificate from the cluster's own CA (`homelab-ca`, created by cert-manager and limited to `home.arpa`; see decisions 5 to 7). Lima forwards ports 80 and 443 to the Mac, and only the Mac can use them, so the dashboard (which has no login yet) is not reachable from the LAN. To open it on the Mac, point the name at the Mac and trust the CA once:

```bash
echo '127.0.0.1 dashboard.home.arpa' | sudo tee -a /etc/hosts       # until a local DNS serves home.arpa
kubectl -n cert-manager get secret homelab-ca-secret -o jsonpath='{.data.tls\.crt}' | base64 -d > ~/homelab-ca.crt
openssl x509 -in ~/homelab-ca.crt -noout -subject -ext nameConstraints  # CN=homelab-ca, Permitted: DNS:home.arpa
security add-trusted-cert -r trustRoot -k ~/Library/Keychains/login.keychain-db ~/homelab-ca.crt  # your user only; asks for your password
open https://dashboard.home.arpa
```

Safari, Chrome and macOS's own `curl` use the keychain; Firefox keeps its own list of CAs. Thanks to the name constraints, a CA you trust this way cannot vouch for any domain outside `home.arpa`. Its key lives only in the cluster, so after `make down` and `make up` there is a new CA: delete the old `homelab-ca` in Keychain Access and trust the new one.

Apps add themselves to the dashboard with `gethomepage.dev/*` annotations on their Ingress; the dashboard's own config is in `apps/base/homepage/config/`.

## Development

Ansible and the linters are pinned in `requirements-dev.txt` and installed in a virtual environment, the same versions CI uses. Every pull request runs `make lint` and `make validate` in GitHub Actions; run the same checks locally before pushing:

```bash
brew install shellcheck kubeconform
python3.14 -m venv .venv          # ansible-core needs Python 3.12 or newer; macOS's python3 is 3.9
source .venv/bin/activate         # needed in every new terminal
pip install -r requirements-dev.txt
make lint                         # yamllint, ansible-lint (production profile) and shellcheck
make validate                     # kustomize + kubeconform on every kustomization.yaml (downloads the schemas)
```

`make validate` checks the manifests against the schemas of the cluster's Kubernetes version (read from `k3s_version`) and Flux's resources against the [Datree CRDs catalog](https://github.com/datreeio/CRDs-catalog), rejecting unknown fields. CustomResourceDefinitions are skipped, since neither source has a schema for them; any other kind without a schema fails. CI pins kubeconform to v0.8.0 with a checksum.

## License

MIT
