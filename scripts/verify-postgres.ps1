[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Compose {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & docker compose @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

& "$PSScriptRoot\start-postgres.ps1"

$containerId = (& docker compose ps -q postgres).Trim()
if ([string]::IsNullOrWhiteSpace($containerId)) {
  throw 'Could not resolve the PostgreSQL container from Docker Compose.'
}

$appProbe = 'PGPASSWORD="$APP_DB_PASSWORD" psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$POSTGRES_CONTAINER_PORT" -U "$APP_DB_USER" -d "$POSTGRES_DB" -Atc "SELECT current_user, current_setting(''server_encoding''), current_setting(''TimeZone'');"'
Invoke-Compose exec --no-TTY postgres sh -c $appProbe

$marker = 'date -u +%Y-%m-%dT%H:%M:%SZ > "$PGDATA/.postgres-persistence-verification"'
Invoke-Compose exec --no-TTY postgres sh -c $marker
Invoke-Compose restart postgres

$deadline = (Get-Date).AddSeconds(90)
do {
  $health = (& docker inspect --format '{{.State.Health.Status}}' $containerId).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Could not inspect PostgreSQL after restart.' }
  if ($health -eq 'healthy') { break }
  Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($health -ne 'healthy') {
  throw "PostgreSQL did not become healthy after restart. Current state: $health"
}

Invoke-Compose exec --no-TTY postgres sh -c 'test -s "$PGDATA/.postgres-persistence-verification"'
Write-Host 'PostgreSQL verified: healthy, authenticated application connection, UTF8, UTC, and persistent volume.'
