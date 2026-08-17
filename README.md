# postgres-app — PostgreSQL 16 + pgAdmin

PostgreSQL 16 for the local `aws/` monorepo, built with
[pgvector](https://github.com/pgvector/pgvector) v0.8.2 (compiled from source)
for embeddings and [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)
for query performance tracking, plus a pinned pgAdmin 8.10 companion. It is the
source database for Kafka Connect (Debezium CDC) and the `postgres-exporter`
scrape in `prometheus/`.

| Container            | Image                                        | Host port                        | Networks           |
| -------------------- | -------------------------------------------- | -------------------------------- | ------------------ |
| postgres-app-db      | `postgres:16-alpine` + pgvector (Dockerfile) | `127.0.0.1:${POSTGRES_PORT}`     | `db_network`, `kafka-network` |
| postgres-app-pgadmin | `dpage/pgadmin4:8.10` (pinned)               | `127.0.0.1:${PGADMIN_PORT:-8080}` | `db_network`       |

Both ports bind to **loopback only**; nothing is exposed on the LAN.

Integrates with the sibling projects:

- **Vault** (`../vault`) — source of `.env` (`secret/postgres-app/dev`) and the AppRole credentials.
- **Kafka Connect** (`../kafka`) — Debezium CDC source via logical replication (`wal_level=logical`, role `debezium`), reached as `postgres-app-db:5432` on `kafka-network`.
- **Prometheus** (`../prometheus`) — `postgres-exporter` scrapes `postgres-app-db:5432` on `kafka-network`.
- **NestJS microservices** — connect with `DATABASE_URL` (loopback) or `DATABASE_URL_NETWORK` (`postgres-app-db:5432`, written into `.env` by `scripts/gen-env.sh`).

## Quick Start (local)

```bash
# 1. Vault running and unsealed (once)
cd ../vault && make dev

# 2. All-in-one: Vault secrets + .env + up
cd ../postgres-app && make all

# 3. Verify
make validate
```

On subsequent starts `make up` is enough.

## Commands

| Command                                | Description                                                                        |
| -------------------------------------- | ---------------------------------------------------------------------------------- |
| `make setup`                           | First time: `vault-secrets` + `env` (idempotent)                                   |
| `make all`                             | `setup` + `up`                                                                     |
| `make up`                              | Starts Postgres + pgAdmin (`compose up -d --build`)                                |
| `make validate`                        | `docker compose config --quiet` + container health check                           |
| `make vault-secrets`                   | Mirrors `DATABASE_URL` into Vault `secret/postgres-app/dev` + AppRole              |
| `make env`                             | Regenerates `.env` from Vault (keeps existing `PGADMIN_*` values)                  |
| `make snapshot` / `make restore`       | `pg_dump` backup into `backups/` / restore a snapshot (prompts for filename)       |
| `make down` / `make restart` / `make stop` / `make logs` / `make ps` | Stack management                                          |
| `make clean`                           | `down -v` (removes the named volumes — destructive)                                |

## Extensions

| Extension          | Purpose                    | Loaded via                                                    |
| ------------------ | -------------------------- | ------------------------------------------------------------- |
| `vector`           | Embeddings / similarity search | `initdb/01-init-extensions.sql`                             |
| `pg_stat_statements` | Query performance tracking  | `initdb/02-pg-stat-statements.sql` + `shared_preload_libraries` (compose `command`) |

`initdb/` scripts run **only on first init** (empty volume). To re-run them,
`make clean` and start again — or `CREATE EXTENSION IF NOT EXISTS …` manually.

## How the secrets flow works (local)

1. `.env` is the **source of truth** for `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`.
2. `scripts/vault-secrets.sh` (`make vault-secrets`) registers the `postgres-app` AppRole (read-only on `secret/data/postgres-app/*`) and writes `DATABASE_URL` + `DB_SSLMODE=disable` to Vault `secret/postgres-app/dev`; AppRole `role_id`/`secret_id` land in `.secrets/` (gitignored).
3. `scripts/gen-env.sh` (`make env`) reads the secret via AppRole login and writes `.env` (gitignored, `chmod 600`), keeping any existing `PGADMIN_*` values.
4. `compose.yml` interpolates `.env` for both containers.

`DATABASE_URL_NETWORK` rewrites the DSN host to `postgres-app-db` so services on `kafka-network` (Kafka Connect, exporters) reach the DB by name.

## Networking

- Internal **`db_network`** (bridge) connects `postgres` and `pgadmin`.
- **`postgres` also joins the external `kafka-network`**, so Kafka Connect (Debezium) and the `postgres-exporter` resolve `postgres-app-db:5432` by name.
- pgAdmin (`postgres-app-pgadmin`) is on `db_network` only; to add a server in the pgAdmin UI use host `postgres` (service name) or `postgres-app-db` with the `POSTGRES_USER`/`POSTGRES_PASSWORD` from `.env`.
- All published ports bind to `127.0.0.1` only.

## Snapshot / restore

```bash
make snapshot                     # pg_dump -> backups/app_db_<timestamp>.sql
make restore                      # prompts for the file, pipes it into psql
```

Snapshots are plain SQL dumps (no scheduled backup). Restoring drops/replaces
the contents of the target database.

## Troubleshooting

| Symptom                                   | Probable cause                        | Fix                                                              |
| ----------------------------------------- | ------------------------------------- | ---------------------------------------------------------------- |
| `make validate` fails                     | Stack not running / unhealthy         | `make up`; wait for the healthcheck (`start_period: 30s`)        |
| `make env` can't log in                   | AppRole creds missing / Vault down    | `make vault-secrets`; `cd ../vault && make dev`                  |
| Extensions missing in a running DB        | Volume pre-dates the initdb scripts   | `make clean`, `make up`, or create them manually                 |
| Kafka Connect can't read the stream       | `wal_level` not `logical` / role missing | compose `command` sets `wal_level=logical`; `initdb/03-debezium-user.sql` creates role `debezium` |

## Structure

```text
├── compose.yml                  # postgres (build) + pgadmin (pinned image)
├── Dockerfile                   # postgres:16-alpine + pgvector v0.8.2
├── initdb/                      # extensions + debezium role (first init only)
├── Makefile                     # orchestrator
├── .env.example                 # non-secret vars and ports
├── scripts/                     # vault-secrets, gen-env
├── docs/                        # conceptual docs
└── .claude/skills/ + .opencode/ # agent skills and commands
```
