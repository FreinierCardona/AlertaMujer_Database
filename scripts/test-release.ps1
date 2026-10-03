[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^alertamujer-db-v\d+\.\d+\.\d+$')]
  [string]$ReleaseTag,

  [switch]$KeepEnvironment
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -ge [Version]'7.3') {
  $PSNativeCommandUseErrorActionPreference = $false
}

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

  $composeErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & docker compose --project-name $testProject @Arguments
  } finally {
    $ErrorActionPreference = $composeErrorActionPreference
  }

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
  $probe = "printf '%s' '$encodedSql' | base64 -d | psql -X -q -v ON_ERROR_STOP=1 -p `"`$POSTGRES_CONTAINER_PORT`" -U `"`$POSTGRES_USER`" -d `"`$POSTGRES_DB`" -At"
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

function Test-SystemConfigurationAcceptance {
  $sql = @'
DO $$
DECLARE
  configuration_row configuration.system_configuration%ROWTYPE;
BEGIN
  SELECT *
    INTO configuration_row
    FROM configuration.system_configuration
   WHERE configuration_id = 1;

  IF NOT FOUND
    OR configuration_row.default_sos_message <> 'Necesito ayuda. Estoy en una emergencia.'
    OR configuration_row.heartbeat_interval_seconds <> 60
    OR configuration_row.offline_timeout_seconds <> 180
    OR configuration_row.max_evidence_count <> 10
    OR configuration_row.max_evidence_size_bytes <> 1048576
    OR configuration_row.max_chat_message_length <> 500
    OR configuration_row.otp_ttl_minutes <> 180
    OR configuration_row.otp_max_attempts <> 5
    OR configuration_row.otp_max_resends <> 3
    OR configuration_row.otp_resend_cooldown_minutes <> 300 THEN
    RAISE EXCEPTION 'HU-DB-008 seed does not match the approved operational configuration.';
  END IF;

  IF (SELECT count(*) FROM configuration.system_configuration) <> 1 THEN
    RAISE EXCEPTION 'HU-DB-008 configuration must contain exactly one row.';
  END IF;

  BEGIN
    INSERT INTO configuration.system_configuration (
      configuration_id, default_sos_message, heartbeat_interval_seconds,
      offline_timeout_seconds, max_evidence_count, max_evidence_size_bytes,
      max_chat_message_length, otp_ttl_minutes, otp_max_attempts,
      otp_max_resends, otp_resend_cooldown_minutes
    ) VALUES (2, 'Second row', 60, 180, 10, 1048576, 500, 180, 5, 3, 300);
    RAISE EXCEPTION 'HU-DB-008 singleton constraint was not enforced.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE configuration.system_configuration
       SET max_evidence_count = 0
     WHERE configuration_id = 1;
    RAISE EXCEPTION 'HU-DB-008 positive limits constraint was not enforced.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE configuration.system_configuration
       SET offline_timeout_seconds = heartbeat_interval_seconds
     WHERE configuration_id = 1;
    RAISE EXCEPTION 'HU-DB-008 timeout-to-heartbeat constraint was not enforced.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'configuration.system_configuration', 'SELECT')
  AND NOT has_table_privilege('alertamujer_app', 'configuration.system_configuration', 'INSERT')
  AND NOT has_table_privilege('alertamujer_app', 'configuration.system_configuration', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'configuration.system_configuration', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'configuration.system_configuration', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-008 acceptance verification failed: $result"
  }
}

function Test-RegistrationRequestsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-02 00:00:00+00';
BEGIN
  INSERT INTO identity.registration_requests (
    registration_request_id, username, first_names, last_names, email,
    phone, password_hash, status, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000009', 'pending.user', 'Pending', 'User',
    'pending.user@example.test', '3000000000', '$2b$12$pending-request-hash',
    'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000010', 'PENDING.USER', 'Other', 'User',
      'username.unique@example.test', '3000000001', '$2b$12$duplicate-username',
      'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed a duplicate pending username.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000011', 'email.unique', 'Other', 'User',
      'PENDING.USER@example.test', '3000000002', '$2b$12$duplicate-email',
      'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed a duplicate pending email.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000012', 'phone.unique', 'Other', 'User',
      'phone.unique@example.test', '3000000000', '$2b$12$duplicate-phone',
      'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed a duplicate pending phone.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000013', 'invalid.status', 'Invalid', 'Status',
      'invalid.status@example.test', '3000000003', '$2b$12$invalid-status',
      'ACTIVE', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed a status outside its lifecycle.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000014', 'invalid.expiry', 'Invalid', 'Expiry',
      'invalid.expiry@example.test', '3000000004', '$2b$12$invalid-expiry',
      'PENDING', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed expires_at that does not follow created_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.registration_requests (
      registration_request_id, username, first_names, last_names, email,
      phone, password_hash, status, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000015', 'invalid.phone', 'Invalid', 'Phone',
      'invalid.phone@example.test', '2000000000', '$2b$12$invalid-phone',
      'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-009 allowed a phone outside the documented format.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO identity.registration_requests (
    registration_request_id, username, first_names, last_names, email,
    phone, password_hash, status, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000016', 'completed.user', 'Completed', 'User',
    'completed.user@example.test', '3000000005', '$2b$12$completed-request-hash',
    'COMPLETED', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
  );
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'identity.registration_requests', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'identity.registration_requests', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.registration_requests', 'SELECT')
  AND NOT has_table_privilege('alertamujer_app', 'identity.registration_requests', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.registration_requests', 'TRUNCATE')
  AND has_column_privilege('alertamujer_app', 'identity.registration_requests', 'registration_request_id', 'SELECT')
  AND NOT has_column_privilege('alertamujer_app', 'identity.registration_requests', 'password_hash', 'SELECT')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-009 acceptance verification failed: $result"
  }
}

function Test-RegistrationRequestsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('identity.registration_requests') IS NULL
  AND to_regnamespace('identity') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-009 rollback isolation verification failed: $result"
  }
}

function Test-UsersAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-02 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000010', 'alerta.user', 'Alerta', 'User',
    'alerta.user@example.test', '3000000010', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, accepted_terms_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000011', 'ALERTA.USER', 'Other', 'User',
      'username.unique@example.test', '3000000011', 'USER', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed a duplicate case-insensitive username.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, accepted_terms_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000012', 'email.unique', 'Other', 'User',
      'ALERTA.USER@example.test', '3000000012', 'USER', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed a duplicate case-insensitive email.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, accepted_terms_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000013', 'phone.unique', 'Other', 'User',
      'phone.unique@example.test', '3000000010', 'USER', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed a duplicate phone.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000014', 'terms.required', 'Terms', 'Required',
      'terms.required@example.test', '3000000014', 'USER', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed self-registration without accepted terms.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000015', 'disabled.no.date', 'Disabled', 'NoDate',
      'disabled.no.date@example.test', '3000000015', 'USER', 'DISABLED',
      'ADMIN_CREATED', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed a disabled account without disabled_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, accepted_terms_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000016', 'invalid.role', 'Invalid', 'Role',
      'invalid.role@example.test', '3000000016', 'CONTACT', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed an undocumented account role.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, accepted_terms_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000017', 'invalid.phone', 'Invalid', 'Phone',
      'invalid.phone@example.test', '2000000017', 'USER', 'ENABLED',
      'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed a phone outside the documented format.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000018', 'entity.admin', 'Entity', 'Admin',
    'entity.admin@example.test', '3000000018', 'ENTITY_ADMIN', 'ENABLED',
    'ADMIN_CREATED', created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.users (
      user_id, username, first_names, last_names, email, phone, role,
      account_status, account_origin, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000019', 'second.admin', 'Second', 'Admin',
      'second.admin@example.test', '3000000019', 'ENTITY_ADMIN', 'ENABLED',
      'ADMIN_CREATED', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-010 allowed more than one ENTITY_ADMIN.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'identity.users', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'identity.users', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'identity.users', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.users', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.users', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-010 acceptance verification failed: $result"
  }
}

function Test-UsersRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('identity.users') IS NULL
  AND to_regclass('identity.ux_users_single_entity_admin') IS NULL
  AND to_regclass('identity.registration_requests') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-010 rollback isolation verification failed: $result"
  }
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
  Invoke-Liquibase -Phase 'update (baseline without HU-DB-009 and HU-DB-010)' -Command @('update', '--label-filter=!hu-db-009 AND !hu-db-010')
  Test-SystemConfigurationAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-009)' -Command @('update', '--label-filter=hu-db-009')
  Test-RegistrationRequestsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-009)' -Command @('rollback-count', '--count=3')
  Test-RegistrationRequestsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-009)' -Command @('update', '--label-filter=hu-db-009')
  Test-SystemConfigurationAcceptance
  Test-RegistrationRequestsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-010)' -Command @('update', '--label-filter=hu-db-010')
  Test-UsersAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-010)' -Command @('rollback-count', '--count=3')
  Test-UsersRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-010)' -Command @('update')
  Test-UsersAcceptance
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
    $cleanupErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & docker compose --project-name $testProject down --volumes --remove-orphans 2>$null
    $ErrorActionPreference = $cleanupErrorActionPreference
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
