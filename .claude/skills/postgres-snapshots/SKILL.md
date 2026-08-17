---
name: postgres-snapshots
description: Create or restore database snapshots for postgres-app. Use when the user asks to back up the database, run make snapshot, restore a dump, or inspect backups/.
---

# Postgres snapshots

Plain SQL dumps via `pg_dump` / `psql`, stored in `backups/` (not automated).

## Create a snapshot

```bash
make snapshot
```

Writes `backups/<POSTGRES_DB>_<YYYYmmdd_HHMMSS>.sql` by piping `pg_dump` from
inside the `postgres-app-db` container. `POSTGRES_USER` / `POSTGRES_DB` are
read from `.env`.

## Restore a snapshot

```bash
make restore
```

Prompts for the filename inside `backups/`, then pipes it into `psql` in the
container. Restoring replaces the contents of the target database.

## Direct commands

```bash
docker exec postgres-app-db pg_dump -U "$(grep -m1 '^POSTGRES_USER=' .env | cut -d= -f2-)" "$(grep -m1 '^POSTGRES_DB=' .env | cut -d= -f2-)" > backups/app_db.sql
docker exec -i postgres-app-db psql -U app_user -d app_db < backups/app_db.sql
```

## Notes

- Snapshots are logical dumps — not a substitute for a scheduled backup.
- `backups/` is not gitignored by default; do not commit dumps containing real
  data.
