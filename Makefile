SHELL := /usr/bin/env bash
# GNU Make 3.82+ only: the make that ships with macOS (3.81) ignores .SHELLFLAGS, so a recipe
# that chains commands in one shell starts with its own `set -euo pipefail`.
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Extra flags for ansible-playbook, e.g.: make provision ANSIBLE_ARGS="--check --diff"
ANSIBLE_ARGS ?=

# Where the kubeconfig is written, outside the repository. Override it with an absolute path,
# e.g. make up KUBECONFIG_FILE=$HOME/.kube/my-lab.yaml. It is passed to Ansible, so the
# default in ansible/inventory/group_vars/k3s_server.yml only applies to direct ansible-playbook runs.
KUBECONFIG_FILE ?= $(HOME)/.kube/homelab.yaml

# kubeconform checks the manifests against the schemas of the cluster's Kubernetes version (read
# from k3s_version, so they never drift apart), and custom resources such as Flux's against the
# Datree CRDs catalog. -strict also rejects unknown fields. CustomResourceDefinitions are skipped by
# name: neither source has a schema for them, they come from upstream projects, and the API server
# checks them on apply. Any other kind without a schema fails, so a typo in a kind is an error.
K8S_VERSION := $(shell sed -nE 's/^k3s_version: "?v([0-9.]+)\+.*/\1/p' ansible/inventory/group_vars/k3s_cluster.yml)
KUBECONFORM_FLAGS := -strict -summary -kubernetes-version $(K8S_VERSION) -skip CustomResourceDefinition \
	-schema-location default \
	-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: help up vms start stop down status ssh-config ping provision kubeconfig lint validate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-15s %s\n", $$1, $$2}'

up: vms provision ## Create the VMs and install K3s on them

vms: ## Create (or start) the Lima VMs
	bash scripts/vms.sh up

start: ## Start the VMs again after a stop
	bash scripts/vms.sh start

stop: ## Stop the VMs but keep their state
	bash scripts/vms.sh stop

down: ## Delete the VMs (this destroys the cluster and its data)
	bash scripts/vms.sh down

status: ## Show the VMs
	bash scripts/vms.sh status

ssh-config: ## Regenerate the SSH config used by Ansible
	bash scripts/vms.sh ssh-config

ping: ssh-config ## Check that Ansible can reach every node
	cd ansible && ansible all -m ansible.builtin.ping

provision: ssh-config ## Run the Ansible playbook (install or upgrade K3s)
	cd ansible && ansible-playbook site.yml -e "k3s_kubeconfig_local_path='$(KUBECONFIG_FILE)'" $(ANSIBLE_ARGS)

kubeconfig: ## Print the KUBECONFIG export line (use: eval "$(make -s kubeconfig)")
	@echo 'export KUBECONFIG="$(KUBECONFIG_FILE)"'

lint: ## Lint YAML, Ansible and shell scripts
	yamllint .
	cd ansible && ansible-lint
	shellcheck scripts/*.sh

validate: ## Validate the Kubernetes manifests (needs kubectl and kubeconform)
	@set -euo pipefail; \
	test -n "$(K8S_VERSION)" || { echo "error: cannot read k3s_version" >&2; exit 1; }; \
	dirs=$$(find . -name kustomization.yaml -not -path './.venv/*' -not -path './.git/*' -exec dirname {} \; | sort); \
	test -n "$$dirs" || { echo "error: no kustomization.yaml found" >&2; exit 1; }; \
	for dir in $$dirs; do \
		echo "==> $${dir#./} (Kubernetes $(K8S_VERSION))"; \
		kubectl kustomize "$$dir" | kubeconform $(KUBECONFORM_FLAGS) -; \
	done
