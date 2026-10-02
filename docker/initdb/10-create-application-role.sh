#!/bin/sh
set -eu

: "${APP_DB_USER:?APP_DB_USER is required}"
: "${APP_DB_PASSWORD:?APP_DB_PASSWORD is required}"
: "${MIGRATOR_DB_USER:?MIGRATOR_DB_USER is required}"
: "${MIGRATOR_DB_PASSWORD:?MIGRATOR_DB_PASSWORD is required}"

case "${APP_DB_USER}" in
  *[!A-Za-z0-9_]* | '')
    echo "APP_DB_USER may contain only letters, numbers, and underscores." >&2
    exit 1
    ;;
esac

case "${MIGRATOR_DB_USER}" in
  *[!A-Za-z0-9_]* | '')
    echo "MIGRATOR_DB_USER may contain only letters, numbers, and underscores." >&2
    exit 1
    ;;
esac

if [ "${APP_DB_USER}" != "alertamujer_app" ] || [ "${MIGRATOR_DB_USER}" != "alertamujer_migrator" ]; then
  echo "APP_DB_USER and MIGRATOR_DB_USER must use their mandated technical role names." >&2
  exit 1
fi

psql --set ON_ERROR_STOP=1 \
  --username "${POSTGRES_USER}" \
  --dbname "${POSTGRES_DB}" \
  --set app_user="${APP_DB_USER}" \
  --set app_password="${APP_DB_PASSWORD}" \
  --set migrator_user="${MIGRATOR_DB_USER}" \
  --set migrator_password="${MIGRATOR_DB_PASSWORD}" <<'SQL'
SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION PASSWORD %L',
  :'app_user',
  :'app_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec

SELECT format(
  'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION PASSWORD %L',
  :'app_user',
  :'app_password'
) \gexec

SELECT 'CREATE ROLE alertamujer_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'alertamujer_owner')
\gexec

SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB CREATEROLE NOINHERIT NOREPLICATION PASSWORD %L',
  :'migrator_user',
  :'migrator_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'migrator_user')
\gexec

SELECT format(
  'ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB CREATEROLE NOINHERIT NOREPLICATION PASSWORD %L',
  :'migrator_user',
  :'migrator_password'
) \gexec

GRANT alertamujer_owner TO :"migrator_user";
ALTER ROLE :"migrator_user" SET ROLE TO alertamujer_owner;

ALTER SCHEMA public OWNER TO alertamujer_owner;

SELECT format(
  'GRANT CREATE ON DATABASE %I TO alertamujer_owner',
  current_database()
) \gexec

DO $$
BEGIN
  IF to_regnamespace('configuration') IS NOT NULL THEN
    ALTER SCHEMA configuration OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('identity') IS NOT NULL THEN
    ALTER SCHEMA identity OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('profile') IS NOT NULL THEN
    ALTER SCHEMA profile OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('contacts') IS NOT NULL THEN
    ALTER SCHEMA contacts OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('emergency') IS NOT NULL THEN
    ALTER SCHEMA emergency OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('notification') IS NOT NULL THEN
    ALTER SCHEMA notification OWNER TO alertamujer_owner;
  END IF;

  IF to_regnamespace('audit') IS NOT NULL THEN
    ALTER SCHEMA audit OWNER TO alertamujer_owner;
  END IF;

  IF to_regclass('public.databasechangelog') IS NOT NULL THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.databasechangelog TO alertamujer_owner;
  END IF;

  IF to_regclass('public.databasechangeloglock') IS NOT NULL THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.databasechangeloglock TO alertamujer_owner;
  END IF;
END
$$;

SELECT format(
  'GRANT CONNECT ON DATABASE %I TO %I',
  current_database(),
  :'app_user'
) \gexec
SQL
