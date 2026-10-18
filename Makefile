SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

.PHONY: help vms start stop down status ssh-config ping lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-15s %s\n", $$1, $$2}'

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

lint: ## Lint YAML, Ansible and shell scripts
	yamllint .
	cd ansible && ansible-lint
	shellcheck scripts/*.sh
