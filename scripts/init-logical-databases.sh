#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
LIGHTSAIL_DB_NAME="${LIGHTSAIL_DB_NAME:-shared-postgres}"
MASTER_DATABASE_NAME="${MASTER_DATABASE_NAME:-postgres}"
MASTER_USERNAME="${MASTER_USERNAME:-postgres_admin}"
ELFICO_DATABASE_NAME="${ELFICO_DATABASE_NAME:-elfico}"
CZYJAFAKTURKA_DATABASE_NAME="${CZYJAFAKTURKA_DATABASE_NAME:-czyjafakturka}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

validate_identifier() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[a-z][a-z0-9_]{0,62}$ ]]; then
    echo "$label must match ^[a-z][a-z0-9_]{0,62}$, got: $value" >&2
    exit 1
  fi
}

get_or_create_secret() {
  local secret_name="$1"
  local database_name="$2"
  local username="$3"
  local password

  if aws secretsmanager describe-secret --region "$AWS_REGION" --secret-id "$secret_name" >/dev/null 2>&1; then
    aws secretsmanager get-secret-value \
      --region "$AWS_REGION" \
      --secret-id "$secret_name" \
      --query SecretString \
      --output text
    return
  fi

  password="$(openssl rand -base64 48 | tr -d '/@\"[:space:]' | cut -c1-48)"
  aws secretsmanager create-secret \
    --region "$AWS_REGION" \
    --name "$secret_name" \
    --description "Application PostgreSQL credentials for $database_name on Lightsail database $LIGHTSAIL_DB_NAME" \
    --secret-string "{\"database\":\"$database_name\",\"username\":\"$username\",\"password\":\"$password\"}" \
    >/dev/null

  aws secretsmanager get-secret-value \
    --region "$AWS_REGION" \
    --secret-id "$secret_name" \
    --query SecretString \
    --output text
}

init_database() {
  local database_name="$1"
  local username="${database_name}_app"
  local secret_name="/lightsail/${LIGHTSAIL_DB_NAME}/${database_name}/app-user"
  local secret_json password

  validate_identifier "$database_name" "database name"
  validate_identifier "$username" "user name"

  secret_json="$(get_or_create_secret "$secret_name" "$database_name" "$username")"
  password="$(jq -r '.password' <<<"$secret_json")"

  PGOPTIONS="-c app.target_database=$database_name -c app.target_user=$username -c app.target_password=$password" psql \
    --host "$DB_HOST" \
    --port "$DB_PORT" \
    --username "$MASTER_USERNAME" \
    --dbname "$MASTER_DATABASE_NAME" \
    --set ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  target_database text := current_setting('app.target_database');
  target_user text := current_setting('app.target_user');
  target_password text := current_setting('app.target_password');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = target_user) THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', target_user, target_password);
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', target_user, target_password);
  END IF;
END
$$;

SELECT format('CREATE DATABASE %I OWNER %I', current_setting('app.target_database'), current_setting('app.target_user'))
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_database
  WHERE datname = current_setting('app.target_database')
)\gexec
SQL

  PGOPTIONS="-c app.target_database=$database_name -c app.target_user=$username -c app.target_password=$password" psql \
    --host "$DB_HOST" \
    --port "$DB_PORT" \
    --username "$MASTER_USERNAME" \
    --dbname "$database_name" \
    --set ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  target_user text := current_setting('app.target_user');
BEGIN
  EXECUTE format('ALTER SCHEMA public OWNER TO %I', target_user);
  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', current_database(), target_user);
  EXECUTE format('GRANT ALL ON SCHEMA public TO %I', target_user);
END
$$;
SQL

  echo "Initialized database $database_name with app user $username and secret $secret_name"
}

require_command aws
require_command jq
require_command openssl
require_command psql

validate_identifier "$ELFICO_DATABASE_NAME" "ELFICO_DATABASE_NAME"
validate_identifier "$CZYJAFAKTURKA_DATABASE_NAME" "CZYJAFAKTURKA_DATABASE_NAME"

DB_HOST="$(aws lightsail get-relational-database \
  --region "$AWS_REGION" \
  --relational-database-name "$LIGHTSAIL_DB_NAME" \
  --query 'relationalDatabase.masterEndpoint.address' \
  --output text)"
DB_PORT="$(aws lightsail get-relational-database \
  --region "$AWS_REGION" \
  --relational-database-name "$LIGHTSAIL_DB_NAME" \
  --query 'relationalDatabase.masterEndpoint.port' \
  --output text)"
export PGPASSWORD
PGPASSWORD="$(aws lightsail get-relational-database-master-user-password \
  --region "$AWS_REGION" \
  --relational-database-name "$LIGHTSAIL_DB_NAME" \
  --query masterUserPassword \
  --output text)"

export DB_HOST DB_PORT MASTER_USERNAME MASTER_DATABASE_NAME

init_database "$ELFICO_DATABASE_NAME"
init_database "$CZYJAFAKTURKA_DATABASE_NAME"
