#!/bin/sh
set -eu

case "${ADMIN_BOOTSTRAP_ENABLED:-}" in
  false)
    exit 0
    ;;
  true)
    ;;
  *)
    echo "ADMIN_BOOTSTRAP_ENABLED must be true or false." >&2
    exit 1
    ;;
esac

: "${ADMIN_BOOTSTRAP_USERNAME:?Bootstrap administrator configuration is incomplete.}"
: "${ADMIN_BOOTSTRAP_FIRST_NAMES:?Bootstrap administrator configuration is incomplete.}"
: "${ADMIN_BOOTSTRAP_LAST_NAMES:?Bootstrap administrator configuration is incomplete.}"
: "${ADMIN_BOOTSTRAP_EMAIL:?Bootstrap administrator configuration is incomplete.}"
: "${ADMIN_BOOTSTRAP_PHONE:?Bootstrap administrator configuration is incomplete.}"
: "${ADMIN_BOOTSTRAP_PASSWORD:?Bootstrap administrator configuration is incomplete.}"
: "${PGHOST:?PostgreSQL host is required.}"
: "${PGPORT:?PostgreSQL port is required.}"
: "${PGDATABASE:?PostgreSQL database is required.}"
: "${PGUSER:?PostgreSQL user is required.}"
: "${PGPASSWORD:?PostgreSQL password is required.}"

if [ "${PGUSER}" != "alertamujer_app" ]; then
  echo "Bootstrap must connect as alertamujer_app." >&2
  exit 1
fi

if [ "$(psql -X -q -v ON_ERROR_STOP=1 -At -c 'SELECT current_user;')" != "alertamujer_app" ]; then
  echo "Bootstrap did not connect as alertamujer_app." >&2
  exit 1
fi

psql -X -q -v ON_ERROR_STOP=1 -At \
  -v admin_username="${ADMIN_BOOTSTRAP_USERNAME}" \
  -v admin_first_names="${ADMIN_BOOTSTRAP_FIRST_NAMES}" \
  -v admin_last_names="${ADMIN_BOOTSTRAP_LAST_NAMES}" \
  -v admin_email="${ADMIN_BOOTSTRAP_EMAIL}" \
  -v admin_phone="${ADMIN_BOOTSTRAP_PHONE}" \
  -v admin_password="${ADMIN_BOOTSTRAP_PASSWORD}" <<'SQL'
SELECT identity.bootstrap_entity_admin(
  :'admin_username',
  :'admin_first_names',
  :'admin_last_names',
  :'admin_email',
  :'admin_phone',
  :'admin_password'
);
SQL
