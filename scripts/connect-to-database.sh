#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
LIGHTSAIL_DB_NAME="${LIGHTSAIL_DB_NAME:-shared-postgres}"

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <elfico|czyjafakturka>

Environment variables:
  AWS_REGION          AWS region containing the database (default: eu-west-1)
  LIGHTSAIL_DB_NAME   Lightsail database resource name (default: shared-postgres)
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

database_name="$1"
case "$database_name" in
  elfico|czyjafakturka)
    ;;
  *)
    echo "Unsupported database: $database_name" >&2
    usage
    exit 1
    ;;
esac

require_command aws
require_command jq
require_command psql

database_json="$(aws lightsail get-relational-database \
  --region "$AWS_REGION" \
  --relational-database-name "$LIGHTSAIL_DB_NAME" \
  --query relationalDatabase \
  --output json)"

database_state="$(jq -r '.state' <<<"$database_json")"
publicly_accessible="$(jq -r '.publiclyAccessible' <<<"$database_json")"

if [[ "$database_state" != "available" ]]; then
  echo "Database $LIGHTSAIL_DB_NAME is not available (state: $database_state)." >&2
  exit 1
fi

if [[ "$publicly_accessible" != "true" ]]; then
  echo "Database $LIGHTSAIL_DB_NAME is not publicly accessible." >&2
  exit 1
fi

db_host="$(jq -r '.masterEndpoint.address' <<<"$database_json")"
db_port="$(jq -r '.masterEndpoint.port' <<<"$database_json")"
secret_id="/lightsail/${LIGHTSAIL_DB_NAME}/${database_name}/app-user"
secret_json="$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$secret_id" \
  --query SecretString \
  --output text)"

db_name="$(jq -er '.database' <<<"$secret_json")"
db_user="$(jq -er '.username' <<<"$secret_json")"
db_password="$(jq -er '.password' <<<"$secret_json")"

echo "Connecting to $db_name on $LIGHTSAIL_DB_NAME ($db_host:$db_port) as $db_user..."
PGPASSWORD="$db_password" PGSSLMODE=require psql \
  --host "$db_host" \
  --port "$db_port" \
  --dbname "$db_name" \
  --username "$db_user"
