---
name: postgres-lifecycle
description: Start, stop and troubleshoot the postgres-app stack. Use when the user asks to make up/down/stop/restart, check container health, connect to the database or pgAdmin, or fix a failed health check.
---

# Postgres stack lifecycle

- `make up` / `make all` — compose up (`-d --build`); `all` also runs
  `vault-secrets` + `env` first.
- `make down` — stop and remove containers (keeps volumes).
- `make stop` / `make restart` — stop without removing / down + up.
- `make ps` — container status.
- `make logs` — follow logs.
- `make clean` — `down -v`, removes the named volumes (`postgres_data`,
  `pgadmin_data`) — destructive.

## Health checks

- `make validate` — `docker compose config --quiet` then:
  `docker inspect -f '{{.Name}} — {{.State.Status}} ({{.State.Health.Status}})' postgres-app-db postgres-app-pgadmin`
- First start takes ~30s (healthcheck `start_period: 30s`).

## Connecting

- DB: `psql -h 127.0.0.1 -U <POSTGRES_USER> -d <POSTGRES_DB>` (from `.env`).
- pgAdmin UI: `http://127.0.0.1:8080`, login with `PGADMIN_DEFAULT_EMAIL` /
  `PGADMIN_DEFAULT_PASSWORD`; when adding a server use host `postgres`
  (service name on `db_network`) or `postgres-app-db` with the `POSTGRES_USER`
  / `POSTGRES_PASSWORD` values.
- Both ports bind to loopback only.

## Troubleshooting

- `make validate` fails: stack not running or still starting — re-run `make up`
  and wait for the healthcheck.
- Missing extensions: `initdb/` only runs on first init; `make clean` + `make up`
  or `CREATE EXTENSION IF NOT EXISTS <name>;` manually.
- Kafka Connect has no CDC stream: check `wal_level=logical` (compose `command`)
  and the `debezium` role (`initdb/03-debezium-user.sql`).
