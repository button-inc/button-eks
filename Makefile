SHELL := /usr/bin/env bash

.PHONY: local-setup
local-setup:
	cat .tool-versions | cut -f 1 -d ' ' | xargs -n 1 asdf plugin-add || true
	asdf plugin-update --all
	asdf install
	asdf reshim
	pip install -r requirements.txt
	pre-commit install
	gitlint install-hook

.PHONY: plan
plan:
	terraform plan | sed -r 's//←/g' > terraform.plan
