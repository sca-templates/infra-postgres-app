# postgres-app — Architecture

> PostgreSQL 16 (pgvector + pg_stat_statements) with a pinned pgAdmin 8.10 companion. DB on `127.0.0.1:${POSTGRES_PORT}` (default 5432), pgAdmin on `127.0.0.1:${PGADMIN_PORT:-8080}` — both **loopback only**.

## Overview

The stack is a Docker Compose deployment inside `aws/postgres-app/`, started locally with `make up` / `make all` (wiring into the root `aws/` orchestrator is pending). It is the source database for Kafka Connect (Debezium CDC) and the `postgres-exporter` in `prometheus/`, and the reference DB for the NestJS microservices.

## Components

| Container            | Image                                        | Host port                        | Networks           | Purpose                                   |
| -------------------- | -------------------------------------------- | -------------------------------- | ----------------- | ----------------------------------------- |
| postgres-app-db      | `postgres:16-alpine` + pgvector v0.8.2 (Dockerfile) | 127.0.0.1:${POSTGRES_PORT} | db_network, kafka-network | Application DB, logical replication source |
| postgres-app-pgadmin | `dpage/pgadmin4:8.10` (pinned)               | 127.0.0.1:${PGADMIN_PORT:-8080}  | db_network         | SQL admin UI                              |

`dpage/pgadmin4:8.10` is pinned to keep the UI stable; the Postgres image is built locally from `postgres:16-alpine` with pgvector v0.8.2 compiled from source (`Dockerfile`, multi-stage).

## Data flow

```mermaid
flowchart LR
  DB[(postgres-app-db :5432)]
  PGA[postgres-app-pgadmin]
  KC[kafka-connect / Debezium]
  PGE[postgres-exporter]
  MS[NestJS microservices]

  DB -- db_network --> PGA
  DB -- kafka-network, logical replication --> KC
  DB -- kafka-network :5432 --> PGE
  DB -- DATABASE_URL* --> MS
```

Solid edges are live integrations. `DATABASE_URL` is the loopback DSN from `.env`; services on `kafka-network` use `DATABASE_URL_NETWORK` (`postgres-app-db:5432`).

## Networking

- **`db_network`** (internal bridge) connects `postgres` and `pgadmin`. pgAdmin reaches Postgres by the service name `postgres`.
- **`postgres` also joins the external `kafka-network`** so Kafka Connect (Debezium) and the `postgres-exporter` resolve `postgres-app-db:5432` by name.
- pgAdmin is on `db_network` only; add the server manually in the UI (host `postgres` or `postgres-app-db`, user/password from `.env`).
- All published ports bind to `127.0.0.1`; nothing is exposed on the LAN.

## Extensions and bootstrap

`initdb/` is mounted at `/docker-entrypoint-initdb.d` and runs **only on first init** (empty volume):

| Script                       | Content                                                             |
| ---------------------------- | ------------------------------------------------------------------- |
| `01-init-extensions.sql`     | `CREATE EXTENSION IF NOT EXISTS vector;` (pgvector)                 |
| `02-pg-stat-statements.sql`  | `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;`                |
| `03-debezium-user.sql`       | Role `debezium` (`REPLICATION LOGIN`), `SELECT` grants on `public`   |

The compose `command` preloads `pg_stat_statements` (`shared_preload_libraries`, `track=all`) and sets `wal_level=logical` for Debezium CDC. On an existing volume, re-run `make clean` + `make up` to re-bootstrap, or create the extensions manually.

## Configuration and secrets

- `.env` is the **source of truth** for `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB`; it is gitignored, `chmod 600`.
- `scripts/vault-secrets.sh` (`make vault-secrets`) registers the `postgres-app` AppRole (read-only policy on `secret/data/postgres-app/*`) and mirrors `DATABASE_URL` + `DB_SSLMODE=disable` into Vault `secret/postgres-app/dev`; AppRole `role_id`/`secret_id` are saved to `.secrets/` (gitignored).
- `scripts/gen-env.sh` (`make env`) logs in with the AppRole credentials, reads the secret and rewrites `.env`, preserving existing `PGADMIN_*` values and emitting `DATABASE_URL_NETWORK` (`postgresql://app_user:***@postgres-app-db:5432/app_db?sslmode=disable`).
- `compose.yml` interpolates `.env` for both containers; pgAdmin gets `PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD` plus `PGADMIN_CONFIG_SERVER_MODE=False`.

## Snapshots and restore

- `make snapshot` pipes `pg_dump` from inside `postgres-app-db` into `backups/<db>_<timestamp>.sql`.
- `make restore` prompts for a file in `backups/` and pipes it into `psql`.
- Plain SQL dumps; no scheduled/automated backup yet. Logical dumps are not a substitute for a retention policy in production.

## Observability and dependencies

- `pg_stat_statements` is preloaded with `track=all` for query-level metrics.
- **Debezium CDC**: Kafka Connect reads this DB through logical replication (`wal_level=logical`); the `debezium` role (`REPLICATION LOGIN`, `SELECT` on `public`) is created by `initdb/03-debezium-user.sql`.
- **postgres-exporter** (`prometheus/`) scrapes `postgres-app-db:5432` on `kafka-network` and publishes `pg_*` metrics to the central Prometheus / Grafana.

## Related

- [README.md](../README.md) — commands, stack lifecycle and troubleshooting.
- Vault note: [04-infrastructure/postgres-app.md (sca-docs)](https://github.com/sca-node-template/sca-docs/blob/main/04-infrastructure/postgres-app.md).
