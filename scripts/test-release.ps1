[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^alertamujer-db-v\d+\.\d+\.\d+$')]
  [string]$ReleaseTag,

  [switch]$KeepEnvironment
)

$ErrorActionPreference = 'Stop'

$testSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 12)
$testProject = "alertamujer-db-release-$testSuffix"
$environmentOverrides = @{
  COMPOSE_PROJECT_NAME = $testProject
  POSTGRES_CONTAINER_NAME = "$testProject-postgres"
  POSTGRES_VOLUME_NAME = "$testProject-data"
  POSTGRES_NETWORK_NAME = "$testProject-network"
  POSTGRES_PORT = '0'
}
$previousEnvironment = @{}

function Invoke-Compose {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

  & docker compose --project-name $testProject @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

function Invoke-Liquibase {
  param(
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][string[]]$Command
  )

  Write-Host "Liquibase phase: $Phase"
  try {
    Invoke-Compose run --rm liquibase @Command
  } catch {
    throw "Liquibase phase '$Phase' failed. Its native output above identifies the failing changeset or precondition. $($_.Exception.Message)"
  }
}

function Wait-ForPostgres {
  $containerId = (& docker compose --project-name $testProject ps -q postgres).Trim()
  if ([string]::IsNullOrWhiteSpace($containerId)) {
    throw 'Could not resolve the isolated PostgreSQL container.'
  }

  $deadline = (Get-Date).AddSeconds(90)
  do {
    $health = (& docker inspect --format '{{.State.Health.Status}}' $containerId).Trim()
    if ($LASTEXITCODE -ne 0) {
      throw 'Could not inspect the isolated PostgreSQL health.'
    }
    if ($health -eq 'healthy') {
      return
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)

  throw "Isolated PostgreSQL did not become healthy. Current state: $health"
}

function Invoke-PostgresScalar {
  param([Parameter(Mandatory)][string]$Sql)

  $encodedSql = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
  $probe = "printf '%s' '$encodedSql' | base64 -d | psql -X -v ON_ERROR_STOP=1 -U `"`$POSTGRES_USER`" -d `"`$POSTGRES_DB`" -At"
  $result = & docker compose --project-name $testProject exec --no-TTY postgres sh -c $probe
  if ($LASTEXITCODE -ne 0) {
    throw 'PostgreSQL verification failed.'
  }

  return ($result | Out-String).Trim()
}

function Get-SchemaFingerprint {
  $dump = & docker compose --project-name $testProject exec --no-TTY postgres sh -c 'pg_dump --port="$POSTGRES_CONTAINER_PORT" --schema-only --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"'
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not calculate the schema fingerprint.'
  }

  # PostgreSQL 17 adds a random psql \restrict token to each dump. It is not
  # part of the schema, so omit it before comparing two schema-only dumps.
  $schemaText = ($dump | Where-Object { $_ -notmatch '^\\(?:un)?restrict ' }) -join "`n"
  $hash = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($schemaText))
  } finally {
    $hash.Dispose()
  }

  return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

try {
  foreach ($name in $environmentOverrides.Keys) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $environmentOverrides[$name], 'Process')
  }

  Invoke-Compose config --quiet
  Invoke-Compose build liquibase
  Invoke-Compose up --detach postgres
  Wait-ForPostgres

  Invoke-Liquibase -Phase 'validate' -Command @('validate')
  Invoke-Liquibase -Phase 'status (clean database)' -Command @('status', '--verbose')
  Invoke-Liquibase -Phase 'update-sql' -Command @('update-sql')
  Invoke-Liquibase -Phase 'update' -Command @('update')
  Invoke-Liquibase -Phase 'history' -Command @('history')

  $changeSetCount = [int](Invoke-PostgresScalar -Sql 'SELECT count(*) FROM public.databasechangelog;')
  if ($changeSetCount -lt 1) {
    throw 'The release test requires at least one applied changeset to exercise rollback.'
  }

  $firstFingerprint = Get-SchemaFingerprint

  Invoke-Liquibase -Phase 'rollback-count-sql (all applied changesets)' -Command @('rollback-count-sql', "--count=$changeSetCount")
  Invoke-Liquibase -Phase 'rollback-count (all applied changesets)' -Command @('rollback-count', "--count=$changeSetCount")

  Invoke-Liquibase -Phase 'updateTestingRollback' -Command @('updateTestingRollback')
  $secondFingerprint = Get-SchemaFingerprint
  if ($secondFingerprint -ne $firstFingerprint) {
    throw 'The schema after rollback and re-apply differs from the first update.'
  }

  Invoke-Liquibase -Phase 'tag' -Command @('tag', "--tag=$ReleaseTag")
  $tagCount = [int](Invoke-PostgresScalar -Sql "SELECT count(*) FROM public.databasechangelog WHERE tag = '$ReleaseTag';")
  if ($tagCount -ne 1) {
    throw "Expected release tag $ReleaseTag exactly once, found $tagCount times."
  }

  Invoke-Liquibase -Phase 'rollback-sql (release tag)' -Command @('rollback-sql', "--tag=$ReleaseTag")
  Invoke-Liquibase -Phase 'second update' -Command @('update')
  Invoke-Liquibase -Phase 'status (final)' -Command @('status', '--verbose')
  Invoke-Liquibase -Phase 'history (final)' -Command @('history')

  $finalChangeSetCount = [int](Invoke-PostgresScalar -Sql 'SELECT count(*) FROM public.databasechangelog;')
  if ($finalChangeSetCount -ne $changeSetCount) {
    throw "The second update changed the applied changeset count from $changeSetCount to $finalChangeSetCount."
  }

  $lockState = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  EXISTS (SELECT 1 FROM public.databasechangeloglock WHERE id = 1 AND locked)
  OR EXISTS (SELECT 1 FROM pg_locks WHERE NOT granted)
THEN 'LOCKED' ELSE 'CLEAR' END;
'@
  if ($lockState -ne 'CLEAR') {
    throw "Liquibase or PostgreSQL left a lock behind: $lockState"
  }

  Write-Host "Release validation passed: $ReleaseTag; $changeSetCount changesets; schema fingerprint $firstFingerprint; no pending locks."
} finally {
  if (-not $KeepEnvironment) {
    & docker compose --project-name $testProject down --volumes --remove-orphans
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Could not fully remove the isolated release environment $testProject."
    }
  } else {
    Write-Warning "Isolated release environment retained: $testProject"
  }

  foreach ($name in $environmentOverrides.Keys) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
  }
}
