# PostgreSQL App

PostgreSQL 16 with [pgvector](https://github.com/pgvector/pgvector) for vector embeddings and [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html) for query performance monitoring, served via Docker Compose with a pgAdmin companion.

## Architecture

```
┌──────────────┐    ┌──────────────┐
│   NestJS     │    │   pgAdmin    │
│     API      │    │   :8080      │
└──────┬───────┘    └──────┬───────┘
       │    db_network     │
       └───────────────────┘
              │
       ┌──────▼───────┐
       │  PostgreSQL  │
       │  :5432       │
       │  pgvector    │
       │  pg_stat_    │
       │  statements  │
       └──────────────┘
```

Secrets are managed via HashiCorp Vault (path: `secret/api-template/dev`). Credentials in `.env` are used only by Docker Compose for container initialization.

## Prerequisites

- Docker >= 24
- Docker Compose >= 2.20
- Make (optional, for snapshot/restore helpers)

## Quick start

```bash
cp .env.example .env
# Edit .env with your own passwords
docker compose up -d
```

The database is ready once the healthcheck passes (about 30 s on first start).

## Configuration

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `app_user` | Database superuser |
| `POSTGRES_PASSWORD` | — | Superuser password |
| `POSTGRES_DB` | `app_db` | Default database |
| `POSTGRES_PORT` | `5432` | Host port (bound to 127.0.0.1 only) |
| `PGADMIN_DEFAULT_EMAIL` | — | pgAdmin login email |
| `PGADMIN_DEFAULT_PASSWORD` | — | pgAdmin login password |
| `PGADMIN_PORT` | `8080` | pgAdmin host port |

## Extensions

| Extension | Purpose | Loaded via |
|---|---|---|
| `vector` | Embeddings / similarity search | `initdb/01-init-extensions.sql` |
| `pg_stat_statements` | Query performance tracking | `initdb/02-pg-stat-statements.sql` + `shared_preload_libraries` in `command` |

> **Existing databases**: If the volume already exists, initdb scripts won't re-run. Run manually:
> ```sql
> CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
> ```

## Usage

### Makefile targets

```bash
make snapshot   # pg_dump the database into backups/
make restore    # restore a snapshot (prompts for filename)
```

### Direct access

```bash
psql -h localhost -U app_user -d app_db
```

The port is only exposed on `127.0.0.1`, so remote connections are blocked at the network level.

## Known gaps

These items are intentionally deferred and should be addressed before moving to production:

| Area | Gap | Priority | Notes |
|---|---|---|---|
| **SSL/TLS** | No certificates configured. Connection uses `sslmode=disable` (defined in the NestJS app via Vault). | Medium | Generate self-signed certs, mount them into the container, update `DATABASE_URL` to `sslmode=require`. Documented in the API repo. |
| **Backups** | No scheduled/automated backups. Only manual snapshots via `make snapshot`. | High | Add a cron job or a backup service (e.g., `pg_dump` to S3 via a sidecar). |
| **Monitoring** | No pgBadger, no dashboards. `pg_stat_statements` is loaded but there is no tool to query it periodically. | Low | Set up pgBadger log analysis or a Grafana dashboard with the postgres exporter. |
| **Replication** | Single instance, no read replicas or failover. | Low | Not needed until read throughput requires it. |
| **Logging** | Default PostgreSQL logging only. No structured logs or log rotation policy. | Low | Configure `log_destination`, `log_line_prefix`, and a log rotation sidecar. |
