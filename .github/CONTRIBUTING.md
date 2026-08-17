# Contributing to postgres-app

> PostgreSQL 16 (pgvector + pg_stat_statements) for the local stack — source DB for Kafka Connect (Debezium CDC) and the `postgres-exporter`, with a pinned pgAdmin 8.10 companion. Docs-as-code: all changes land through a PR with review.

## Ground rules

- **English only** — notes, commits, and PR descriptions are written in English.
- **No secrets in the repo** — `.env` is gitignored and generated from Vault; never commit tokens, role IDs or passwords. New configuration with secrets goes through `scripts/vault-secrets.sh` and `scripts/gen-env.sh` (AppRole credentials stay in `.secrets/`, gitignored).
- **Docs-as-code** — every change goes through a pull request and is reviewed.

## Repository layout

```text
compose.yml              Services: postgres (build) + pgadmin (pinned image)
Dockerfile               postgres:16-alpine + pgvector v0.8.2 (multi-stage build)
initdb/                  01 extensions, 02 pg_stat_statements, 03 debezium role
Makefile                 help | setup | vault-secrets | env | up | all | down | stop | restart | logs | ps | validate | snapshot | restore | clean
scripts/                 vault-secrets.sh | gen-env.sh
.env.example             Non-secret defaults and ports (7 keys)
.github/                 CI, PR template, dependabot, markdown link-check config
```

## Adding or changing a database feature

1. Extensions or bootstrap SQL go in `initdb/` (ordered, idempotent where possible) — remember they run only on first init.
2. New runtime parameters (e.g. `wal_level`, `shared_preload_libraries`) go in the compose `command` on the `postgres` service.
3. If a new host port appears, add it to `.env.example` and the compose file.
4. New credentials go through `scripts/vault-secrets.sh` (mirror into Vault `secret/postgres-app/dev`) and `scripts/gen-env.sh` (regenerate `.env`).
5. Update the README tables (ports, extensions, commands) and `docs/architecture.md`.

## Contribution flow

1. Branch off `main`: `git checkout -b feat/<topic>`.
2. Create or edit the files following the conventions above.
3. Run the checks (see Tooling).
4. Open a PR and fill the checklist from the template.

## Definition of done

- [ ] Content is in English.
- [ ] `.env.example` is updated when new variables are added.
- [ ] No secrets or tokens are committed (`.env`, `.secrets/` stay gitignored).
- [ ] `make validate` passes locally (compose config + container health).
- [ ] `docker compose -f compose.yml config --quiet` passes.
- [ ] `shellcheck scripts/*.sh` passes.
- [ ] `markdownlint` and link check pass (CI runs them too).
- [ ] `README.md` is updated when the stack, ports or commands change.

## Tooling

```sh
# Validate the stack (compose config + container health)
make validate

# Lint markdown
npx --yes markdownlint-cli2 README.md AGENTS.md CLAUDE.md .github/PULL_REQUEST_TEMPLATE.md .github/CONTRIBUTING.md docs/**/*.md .claude/skills/**/SKILL.md .opencode/command/*.md

# Check links in a single file (config lives in .github/)
npx --yes markdown-link-check -c .github/markdown-link-check.json <file>
```

## License

This repository is licensed under the MIT License (see [LICENSE](../LICENSE)).
