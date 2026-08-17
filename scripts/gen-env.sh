#!/usr/bin/env bash
# gen-env.sh — Generates .env from Vault via the postgres-app AppRole (local).
#   Reads secret/postgres-app/dev (DATABASE_URL, DB_SSLMODE) and writes .env
#   (gitignored, chmod 600) for compose interpolation. The DATABASE_URL host is
#   rewritten to postgres-app-db so services on kafka-network reach the DB.
# Usage: make env
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="${VAULT_DIR:-$PROJECT_DIR/../vault}"
SECRETS_DIR="$VAULT_DIR/data/secrets"
SECRET_LOCAL_DIR="$PROJECT_DIR/.secrets"
OUT="$PROJECT_DIR/.env"
VAULT_ENV="${VAULT_ENV:-dev}"

VAULT_ADDR="$(grep -m1 '^VAULT_ADDR=' "$VAULT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '\n\r')"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8201}"
export VAULT_SKIP_VERIFY=true

if ! curl -sk -m 5 -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "ERROR: Vault is not reachable at $VAULT_ADDR. Start it with: cd ../vault && make up && make unseal"
  exit 1
fi

# AppRole auth (role_id/secret_id from repo .secrets/, fallback to vault data/secrets)
ROLE_ID="$(cat "$SECRET_LOCAL_DIR/approle-postgres-app-roleid.txt" 2>/dev/null || \
  cat "$SECRETS_DIR/approle-postgres-app-roleid.txt" 2>/dev/null || true)"
SECRET_ID="$(cat "$SECRET_LOCAL_DIR/approle-postgres-app-secretid.txt" 2>/dev/null || \
  cat "$SECRETS_DIR/approle-postgres-app-secretid.txt" 2>/dev/null || true)"
if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
  echo "ERROR: AppRole credentials missing. Run first: make vault-secrets"
  exit 1
fi

LOGIN_JSON="$(curl -sk -X POST -H "Content-Type: application/json" \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  "$VAULT_ADDR/v1/auth/approle/login")"
VAULT_TOKEN="$(echo "$LOGIN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["auth"]["client_token"])' 2>/dev/null || true)"
if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: AppRole login failed. Re-run: make vault-secrets"
  exit 1
fi

echo "=== Reading DATABASE_URL from Vault (AppRole: postgres-app) ==="
PG_JSON="$(curl -sk -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/postgres-app/$VAULT_ENV" \
  | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)["data"]["data"]))')"

DATABASE_URL="$(echo "$PG_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["DATABASE_URL"])')"
DB_SSLMODE="$(echo "$PG_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("DB_SSLMODE", "disable"))')"

if [ -z "$DATABASE_URL" ]; then
  echo "ERROR: DATABASE_URL is empty. Run first: make vault-secrets"
  exit 1
fi

# parse DATABASE_URL -> postgresql://user:pass@localhost:port/db
POSTGRES_USER="$(echo "$DATABASE_URL" | sed -E 's|^.*://([^:]+):.*|\1|')"
POSTGRES_PASSWORD="$(echo "$DATABASE_URL" | sed -E 's|^.*://[^:]+:([^@]+)@.*|\1|')"
POSTGRES_DB="$(echo "$DATABASE_URL" | sed -E 's|^.*/([^/?]+)(\?.*)?$|\1|')"
POSTGRES_PORT="$(echo "$DATABASE_URL" | sed -E 's|^.*:([0-9]+)/.*|\1|')"

# Preserve pgAdmin values from an existing .env, else defaults.
PGADMIN_DEFAULT_EMAIL="$(grep -m1 '^PGADMIN_DEFAULT_EMAIL=' "$OUT" 2>/dev/null | cut -d= -f2- | tr -d '\n\r' || true)"
PGADMIN_DEFAULT_EMAIL="${PGADMIN_DEFAULT_EMAIL:-admin@example.com}"
PGADMIN_DEFAULT_PASSWORD="$(grep -m1 '^PGADMIN_DEFAULT_PASSWORD=' "$OUT" 2>/dev/null | cut -d= -f2- | tr -d '\n\r' || true)"
PGADMIN_DEFAULT_PASSWORD="${PGADMIN_DEFAULT_PASSWORD:-admin}"
PGADMIN_PORT="$(grep -m1 '^PGADMIN_PORT=' "$OUT" 2>/dev/null | cut -d= -f2- | tr -d '\n\r' || true)"
PGADMIN_PORT="${PGADMIN_PORT:-8080}"

# Keep the loopback DSN as DATABASE_URL (bootstrap/gateway reference) plus a
# kafka-network variant for sibling services.
DATABASE_URL_NETWORK="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-app-db:5432/${POSTGRES_DB}?sslmode=${DB_SSLMODE}"

cat > "$OUT" <<EOF
ENVIRONMENT=${VAULT_ENV:-local}

# PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_PORT=${POSTGRES_PORT}
DATABASE_URL=${DATABASE_URL}?sslmode=${DB_SSLMODE}
DATABASE_URL_NETWORK=${DATABASE_URL_NETWORK}

# pgAdmin
PGADMIN_DEFAULT_EMAIL=${PGADMIN_DEFAULT_EMAIL}
PGADMIN_DEFAULT_PASSWORD=${PGADMIN_DEFAULT_PASSWORD}
PGADMIN_PORT=${PGADMIN_PORT}
EOF

chmod 0600 "$OUT"
echo ".env generated from Vault ($VAULT_ENV). Source: secret/postgres-app/$VAULT_ENV (AppRole: postgres-app)"
