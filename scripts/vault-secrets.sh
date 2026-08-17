#!/usr/bin/env bash
# vault-secrets.sh — Bootstraps postgres-app secrets in Vault (idempotent).
#   1. Ensures postgres-app/.env exists (source of truth for POSTGRES_*)
#   2. Registers the "postgres-app" AppRole (read-only policy on
#      secret/data/postgres-app/*)
#   3. Saves the AppRole role_id/secret_id into .secrets/ (gitignored)
#   4. Stores DATABASE_URL + DB_SSLMODE in secret/postgres-app/dev
# Usage: make vault-secrets   (FORCE=1 to overwrite)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="${VAULT_DIR:-$PROJECT_DIR/../vault}"
SECRETS_DIR="$VAULT_DIR/data/secrets"
SECRET_LOCAL_DIR="$PROJECT_DIR/.secrets"
VAULT_ENV="${VAULT_ENV:-dev}"

VAULT_ADDR="$(grep -m1 '^VAULT_ADDR=' "$VAULT_DIR/.env" 2>/dev/null | cut -d= -f2- | tr -d '\n\r')"
VAULT_ADDR="${VAULT_ADDR:-https://127.0.0.1:8201}"
export VAULT_SKIP_VERIFY=true

VAULT_TOKEN="$(cat "$SECRETS_DIR/root-token.txt" 2>/dev/null || \
  docker exec prod-vault-1 cat /vault/data/secrets/root-token.txt 2>/dev/null | tr -d '\n\r' || true)"
if [ -z "$VAULT_TOKEN" ]; then
  echo "ERROR: Could not obtain the Vault token. Is it running? (cd ../vault && make up && make unseal)"
  exit 1
fi

if ! curl -sk -m 5 -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "ERROR: Vault is not reachable at $VAULT_ADDR. Start it with: cd ../vault && make up && make unseal"
  exit 1
fi

vault_get() { curl -sk -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/$1"; }
vault_post() { curl -sk -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" -X POST "$VAULT_ADDR/v1/$1" -d "$2"; }

gen_pass() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24; }

echo "=== 1. Ensure postgres-app/.env exists ==="
if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo "Generating $PROJECT_DIR/.env (fresh clone)..."
  if [ -f "$PROJECT_DIR/.env.example" ]; then
    PG_PASS="$(gen_pass)"
    PGADMIN_PASS="$(gen_pass)"
    sed -e "s|your_own_strong_password_here|${PG_PASS}|" \
        -e "s|your_own_strong_password_here|${PGADMIN_PASS}|" \
        -e "s|your_email@example.com|admin@example.com|g" \
        "$PROJECT_DIR/.env.example" > "$PROJECT_DIR/.env"
  else
    cat > "$PROJECT_DIR/.env" <<EOF
POSTGRES_USER=app_user
POSTGRES_PASSWORD=$(gen_pass)
POSTGRES_DB=app_db
POSTGRES_PORT=5432
PGADMIN_DEFAULT_EMAIL=admin@example.com
PGADMIN_DEFAULT_PASSWORD=$(gen_pass)
PGADMIN_PORT=8080
EOF
  fi
  chmod 0600 "$PROJECT_DIR/.env"
else
  echo "$PROJECT_DIR/.env already exists (values preserved)."
fi

POSTGRES_USER="$(grep -m1 '^POSTGRES_USER=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\n\r')"
POSTGRES_PASSWORD="$(grep -m1 '^POSTGRES_PASSWORD=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\n\r')"
POSTGRES_DB="$(grep -m1 '^POSTGRES_DB=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\n\r')"
POSTGRES_PORT="$(grep -m1 '^POSTGRES_PORT=' "$PROJECT_DIR/.env" | cut -d= -f2- | tr -d '\n\r')"

DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT}/${POSTGRES_DB}"

echo ""
echo "=== 2. AppRole 'postgres-app' ==="
ROLE_CODE="$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/auth/approle/role/postgres-app")"
if [ "$ROLE_CODE" = "404" ]; then
  echo "Registering postgres-app service in Vault..."
  if [ -x "$VAULT_DIR/scripts/add-service.sh" ]; then
    bash "$VAULT_DIR/scripts/add-service.sh" postgres-app "" --read-policy "secret/data/postgres-app/*"
  else
    echo "ERROR: $VAULT_DIR/scripts/add-service.sh not found"
    exit 1
  fi
else
  echo "AppRole postgres-app already exists. (FORCE=1 to recreate it)"
fi

mkdir -p "$SECRET_LOCAL_DIR"
cp "$SECRETS_DIR/approle-postgres-app-roleid.txt" "$SECRET_LOCAL_DIR/approle-postgres-app-roleid.txt"
cp "$SECRETS_DIR/approle-postgres-app-secretid.txt" "$SECRET_LOCAL_DIR/approle-postgres-app-secretid.txt"
chmod 0600 "$SECRET_LOCAL_DIR/approle-postgres-app-roleid.txt" "$SECRET_LOCAL_DIR/approle-postgres-app-secretid.txt"
echo "AppRole credentials saved to $SECRET_LOCAL_DIR/ (gitignored)"

echo ""
echo "=== 3. DATABASE_URL in secret/postgres-app/$VAULT_ENV ==="
EXISTING="$(vault_get "secret/data/postgres-app/$VAULT_ENV")"

if echo "$EXISTING" | grep -q '"DATABASE_URL"' && [ "${FORCE:-0}" != "1" ]; then
  echo "DATABASE_URL already exists. (FORCE=1 to overwrite/refresh)"
else
  echo "Writing DATABASE_URL to secret/postgres-app/$VAULT_ENV..."
  PAYLOAD=$(python3 - "$DATABASE_URL" <<'PY'
import json, sys
payload = {"data": {"DATABASE_URL": sys.argv[1], "DB_SSLMODE": "disable"}}
print(json.dumps(payload))
PY
)
  vault_post "secret/data/postgres-app/$VAULT_ENV" "$PAYLOAD"
  echo "DATABASE_URL written."
fi

echo ""
echo "Next step: make env"
