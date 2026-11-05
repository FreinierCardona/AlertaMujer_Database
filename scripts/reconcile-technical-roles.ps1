[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

& docker compose up -d --wait postgres
if ($LASTEXITCODE -ne 0) {
  throw "docker compose up -d --wait postgres failed with exit code $LASTEXITCODE."
}

& docker compose exec --no-TTY postgres sh -c 'PGPORT="$POSTGRES_CONTAINER_PORT" /docker-entrypoint-initdb.d/10-create-application-role.sh'
if ($LASTEXITCODE -ne 0) {
  throw "Technical role reconciliation failed with exit code $LASTEXITCODE."
}

Write-Host 'Technical roles reconciled from .env without exposing passwords in Liquibase files.'
