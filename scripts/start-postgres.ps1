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

Invoke-Compose config --quiet
Invoke-Compose up --detach postgres

$containerId = (& docker compose ps -q postgres).Trim()
if ([string]::IsNullOrWhiteSpace($containerId)) {
  throw 'Could not resolve the PostgreSQL container from Docker Compose.'
}

$deadline = (Get-Date).AddSeconds(90)
do {
  $health = (& docker inspect --format '{{.State.Health.Status}}' $containerId).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not inspect the PostgreSQL container health.'
  }
  if ($health -eq 'healthy') { break }
  Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if ($health -ne 'healthy') {
  throw "PostgreSQL did not become healthy. Current state: $health"
}

$containerPort = (& docker exec $containerId sh -c 'printf "%s" "$POSTGRES_CONTAINER_PORT"').Trim()
if ([string]::IsNullOrWhiteSpace($containerPort)) {
  throw 'Could not resolve the PostgreSQL internal port from the container.'
}

$publishedEndpoint = (& docker port $containerId "$containerPort/tcp").Trim()
if ([string]::IsNullOrWhiteSpace($publishedEndpoint)) {
  throw 'Could not resolve the PostgreSQL published port from Docker.'
}

Write-Host "PostgreSQL is healthy at $publishedEndpoint."
