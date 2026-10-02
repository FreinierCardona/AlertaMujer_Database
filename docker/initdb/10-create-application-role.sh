#!/bin/sh
set -eu

: "${APP_DB_USER:?APP_DB_USER is required}"
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD is required}"

case "${APP_DB_USER}" in
  *[!A-Za-z0-9_]* | '')
    echo "APP_DB_USER may contain only letters, numbers, and underscores." >&2
    exit 1
    ;;
esac

psql --set ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  --set app_user="${APP_DB_USER}" \
  --set app_password="${APP_DB_PASSWORD}" <<'SQL'
CREATE ROLE :"app_user"
  LOGIN
  NOSUPERUSER
  NOCREATEDB
  NOCREATEROLE
  NOINHERIT
  NOREPLICATION
  PASSWORD :'app_password';

SELECT format(
  'GRANT CONNECT ON DATABASE %I TO %I',
  current_database(),
  :'app_user'
) \gexec
SQL
