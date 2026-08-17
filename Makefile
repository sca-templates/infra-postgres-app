SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

COMPOSE_FILE := compose.yml
COMPOSE_PROJECT_NAME := postgres-app
COMPOSE := docker compose -f $(COMPOSE_FILE) -p $(COMPOSE_PROJECT_NAME)
VAULT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))/../vault
SCRIPTS := scripts

.PHONY: help
help:
	@echo 'postgres-app — Makefile'
	@echo ''
	@echo '  make help          Show all targets'
	@echo '  make setup         First time: vault-secrets + env'
	@echo '  make vault-secrets Write DATABASE_URL to Vault (secret/postgres-app/dev)'
	@echo '  make env           Generate .env from Vault (AppRole postgres-app)'
	@echo '  make up            Start Postgres + pgAdmin containers'
	@echo '  make all           setup + up'
	@echo '  make down          Stop and remove containers'
	@echo '  make restart       Restart'
	@echo '  make stop          Stop'
	@echo '  make logs          Tail logs'
	@echo '  make ps            Show container status'
	@echo '  make validate      compose config + health'
	@echo '  make snapshot      pg_dump a backup to backups/'
	@echo '  make restore       Restore a backup from backups/'
	@echo '  make clean         stop + remove containers + prune volumes (destructive)'

.PHONY: setup
setup: vault-secrets env

.PHONY: vault-secrets
vault-secrets:
	@echo '=== Registering postgres-app AppRole + secrets in Vault ==='
	@$(SCRIPTS)/vault-secrets.sh

.PHONY: env
env:
	@echo '=== Generating .env from Vault ==='
	@$(SCRIPTS)/gen-env.sh

.PHONY: up
up:
	@echo '=== Starting postgres-app ==='
	$(COMPOSE) up -d --build

.PHONY: all
all: setup up

.PHONY: down
down:
	@echo '=== Stopping postgres-app ==='
	$(COMPOSE) down

.PHONY: restart
restart: down up

.PHONY: stop
stop:
	$(COMPOSE) stop

.PHONY: logs
logs:
	$(COMPOSE) logs -f

.PHONY: ps
ps:
	$(COMPOSE) ps

.PHONY: validate
validate:
	@echo '=== compose config ==='
	$(COMPOSE) config --quiet
	@echo '=== health ==='
	@docker inspect -f '{{.Name}} — {{.State.Status}} ({{.State.Health.Status}})' postgres-app-db postgres-app-pgadmin

.PHONY: snapshot
snapshot:
	@mkdir -p backups
	@docker exec postgres-app-db pg_dump -U "$$(grep -m1 '^POSTGRES_USER=' .env | cut -d= -f2-)" "$$(grep -m1 '^POSTGRES_DB=' .env | cut -d= -f2-)" > backups/$$(grep -m1 '^POSTGRES_DB=' .env | cut -d= -f2-)_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Snapshot created: backups/$$(grep -m1 '^POSTGRES_DB=' .env | cut -d= -f2-)_$$(date +%Y%m%d_%H%M%S).sql"

.PHONY: restore
restore:
	@read -p "Snapshot file: " file; \
	docker exec -i postgres-app-db psql -U "$$(grep -m1 '^POSTGRES_USER=' .env | cut -d= -f2-)" -d "$$(grep -m1 '^POSTGRES_DB=' .env | cut -d= -f2-)" < backups/$$file
	@echo "Restored from backups/$$file"

.PHONY: clean
clean:
	@echo '=== Cleaning up postgres-app ==='
	-$(COMPOSE) down -v 2>/dev/null || true
	@echo 'Done.'
