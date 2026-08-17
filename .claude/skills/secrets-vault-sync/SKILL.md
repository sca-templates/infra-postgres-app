---
name: secrets-vault-sync
description: Sync postgres-app secrets between .env and Vault. Use when the user asks to run make vault-secrets or make env, regenerate .env, bootstrap the AppRole, or fix a DATABASE_URL / Vault login problem.
---

# Secrets / Vault sync

`.env` is the source of truth for `POSTGRES_USER` / `POSTGRES_PASSWORD` /
`POSTGRES_DB`; Vault `secret/postgres-app/dev` mirrors `DATABASE_URL`.

## Steps

1. `make vault-secrets` (idempotent):
   - ensures `.env` exists (generated from `.env.example` if missing),
   - registers the `postgres-app` AppRole (read-only policy on
     `secret/data/postgres-app/*`) via `../vault/scripts/add-service.sh`,
   - copies AppRole `role_id` / `secret_id` into `.secrets/` (gitignored),
   - writes `DATABASE_URL` + `DB_SSLMODE=disable` to `secret/postgres-app/dev`.
   `FORCE=1` overwrites an existing secret / recreates the role.
2. `make env` (gen-env.sh):
   - logs in with the AppRole credentials from `.secrets/`,
   - reads `DATABASE_URL` from Vault and writes `.env` (`chmod 600`),
   - keeps existing `PGADMIN_*` values from the current `.env`,
   - writes `DATABASE_URL_NETWORK` with the host rewritten to
     `postgres-app-db` for services on `kafka-network`.

## Troubleshooting

- `make env` can't log in: AppRole creds missing → run `make vault-secrets`.
- Vault unreachable: `cd ../vault && make dev` (up + unseal).
- After a Vault re-init the KV secret survives, but re-run `make env` to
  refresh `.env`.
