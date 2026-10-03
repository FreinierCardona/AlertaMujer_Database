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

function Test-UserCredentialsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-02 00:00:00+00';
BEGIN
  INSERT INTO identity.user_credentials (
    credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000111',
    '00000000-0000-0000-0000-000000000010',
    '$2b$12$user-credential-hash', created_at_value, created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.user_credentials (
      credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000112',
      '00000000-0000-0000-0000-000000000010',
      '$2b$12$duplicate-user-credential-hash', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-011 allowed more than one credential for a user.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_credentials (
      credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000113',
      '00000000-0000-0000-0000-000000000999',
      '$2b$12$orphan-credential-hash', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-011 allowed an orphan credential.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000020', 'credential.blank', 'Credential', 'Blank',
    'credential.blank@example.test', '3000000020', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.user_credentials (
      credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000114',
      '00000000-0000-0000-0000-000000000020',
      '   ', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-011 allowed a blank password hash.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000021', 'credential.long', 'Credential', 'Long',
    'credential.long@example.test', '3000000021', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.user_credentials (
      credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000115',
      '00000000-0000-0000-0000-000000000021',
      repeat('x', 256), created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-011 allowed a password hash longer than 255 characters.';
  EXCEPTION WHEN string_data_right_truncation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000022', 'credential.cascade', 'Credential', 'Cascade',
    'credential.cascade@example.test', '3000000022', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO identity.user_credentials (
    credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000116',
    '00000000-0000-0000-0000-000000000022',
    '$2b$12$cascade-credential-hash', created_at_value, created_at_value, created_at_value
  );

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000022';

  IF EXISTS (
    SELECT 1
      FROM identity.user_credentials
     WHERE credential_id = '00000000-0000-0000-0000-000000000116'
  ) THEN
    RAISE EXCEPTION 'HU-DB-011 did not delete the credential when its user was deleted.';
  END IF;

  DELETE FROM identity.user_credentials
   WHERE credential_id = '00000000-0000-0000-0000-000000000111';

  DELETE FROM identity.users
   WHERE user_id IN (
     '00000000-0000-0000-0000-000000000020',
     '00000000-0000-0000-0000-000000000021'
   );
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'identity.user_credentials', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'identity.user_credentials', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_credentials', 'SELECT')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_credentials', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_credentials', 'TRUNCATE')
  AND has_column_privilege('alertamujer_app', 'identity.user_credentials', 'credential_id', 'SELECT')
  AND NOT has_column_privilege('alertamujer_app', 'identity.user_credentials', 'password_hash', 'SELECT')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-011 acceptance verification failed: $result"
  }
}

function Test-UserCredentialsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('identity.user_credentials') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-011 rollback isolation verification failed: $result"
  }
}

function Test-UserVerificationCodesAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-02 00:00:00+00';
BEGIN
  INSERT INTO identity.user_credentials (
    credential_id, user_id, password_hash, password_updated_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000131',
    '00000000-0000-0000-0000-000000000010',
    '$2b$12$user-credential-hash', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO identity.user_verification_codes (
    verification_code_id, user_id, channel, purpose, destination_snapshot,
    code_hash, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000121',
    '00000000-0000-0000-0000-000000000010', 'EMAIL', 'PASSWORD_RESET',
    'alerta.user@example.test', '$2b$12$user-otp-hash',
    created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
  );

  INSERT INTO identity.user_verification_codes (
    verification_code_id, registration_request_id, channel, purpose, destination_snapshot,
    code_hash, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000122',
    '00000000-0000-0000-0000-000000000009', 'SMS', 'PHONE_VERIFICATION',
    '3000000000', '$2b$12$registration-otp-hash',
    created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, channel, purpose, destination_snapshot, code_hash,
      expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000123', 'EMAIL', 'EMAIL_VERIFICATION',
      'orphan@example.test', '$2b$12$orphan-otp-hash',
      created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed an OTP without an identity context.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, user_id, registration_request_id, channel, purpose,
      destination_snapshot, code_hash, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000124',
      '00000000-0000-0000-0000-000000000010',
      '00000000-0000-0000-0000-000000000009', 'EMAIL', 'EMAIL_VERIFICATION',
      'both@example.test', '$2b$12$both-contexts-otp-hash',
      created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed an OTP in both identity contexts.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, user_id, channel, purpose, destination_snapshot,
      code_hash, expires_at, attempt_count, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000125',
      '00000000-0000-0000-0000-000000000010', 'EMAIL', 'PASSWORD_RESET',
      'attempts@example.test', '$2b$12$attempts-otp-hash',
      created_at_value + INTERVAL '3 hours', 6, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed attempt_count above the documented maximum.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, user_id, channel, purpose, destination_snapshot,
      code_hash, expires_at, resend_number, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000126',
      '00000000-0000-0000-0000-000000000010', 'EMAIL', 'PASSWORD_RESET',
      'resends@example.test', '$2b$12$resends-otp-hash',
      created_at_value + INTERVAL '3 hours', 4, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed resend_number above the documented maximum.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, user_id, channel, purpose, destination_snapshot,
      code_hash, expires_at, max_attempts, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000127',
      '00000000-0000-0000-0000-000000000010', 'EMAIL', 'PASSWORD_RESET',
      'maximum@example.test', '$2b$12$maximum-otp-hash',
      created_at_value + INTERVAL '3 hours', 4, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed a max_attempts value other than five.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_verification_codes (
      verification_code_id, user_id, channel, purpose, destination_snapshot,
      code_hash, expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000128',
      '00000000-0000-0000-0000-000000000010', 'EMAIL', 'PASSWORD_RESET',
      'expired@example.test', '$2b$12$expired-otp-hash',
      created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-012 allowed an expiration that does not follow creation.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000030', 'otp.cascade.user', 'Otp', 'Cascade',
    'otp.cascade.user@example.test', '3000000030', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO identity.user_verification_codes (
    verification_code_id, user_id, channel, purpose, destination_snapshot,
    code_hash, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000129',
    '00000000-0000-0000-0000-000000000030', 'EMAIL', 'PROFILE_CONTACT_CHANGE',
    'otp.cascade.user@example.test', '$2b$12$user-cascade-otp-hash',
    created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
  );

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000030';

  IF EXISTS (
    SELECT 1 FROM identity.user_verification_codes
     WHERE verification_code_id = '00000000-0000-0000-0000-000000000129'
  ) THEN
    RAISE EXCEPTION 'HU-DB-012 did not delete OTPs when their user context was deleted.';
  END IF;

  INSERT INTO identity.registration_requests (
    registration_request_id, username, first_names, last_names, email, phone,
    password_hash, status, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000017', 'otp.cascade.request', 'Otp', 'Request',
    'otp.cascade.request@example.test', '3000000031', '$2b$12$otp-request-hash',
    'PENDING', created_at_value + INTERVAL '1 day', created_at_value, created_at_value
  );

  INSERT INTO identity.user_verification_codes (
    verification_code_id, registration_request_id, channel, purpose, destination_snapshot,
    code_hash, expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000130',
    '00000000-0000-0000-0000-000000000017', 'SMS', 'PHONE_VERIFICATION',
    '3000000031', '$2b$12$request-cascade-otp-hash',
    created_at_value + INTERVAL '3 hours', created_at_value, created_at_value
  );

  DELETE FROM identity.registration_requests
   WHERE registration_request_id = '00000000-0000-0000-0000-000000000017';

  IF EXISTS (
    SELECT 1 FROM identity.user_verification_codes
     WHERE verification_code_id = '00000000-0000-0000-0000-000000000130'
  ) THEN
    RAISE EXCEPTION 'HU-DB-012 did not delete OTPs when their registration context was deleted.';
  END IF;

END
$$;

SET ROLE alertamujer_app;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'identity.user_verification_codes', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'identity.user_verification_codes', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_verification_codes', 'SELECT')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_verification_codes', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_verification_codes', 'TRUNCATE')
  AND has_column_privilege('alertamujer_app', 'identity.user_verification_codes', 'verification_code_id', 'SELECT')
  AND NOT has_column_privilege('alertamujer_app', 'identity.user_verification_codes', 'code_hash', 'SELECT')
  AND has_function_privilege('alertamujer_app', 'identity.get_user_password_hash(uuid)', 'EXECUTE')
  AND has_function_privilege('alertamujer_app', 'identity.get_registration_password_hash(uuid)', 'EXECUTE')
  AND has_function_privilege('alertamujer_app', 'identity.get_verification_code_hash(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'identity.get_user_password_hash(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'identity.get_registration_password_hash(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'identity.get_verification_code_hash(uuid)', 'EXECUTE')
  AND identity.get_user_password_hash('00000000-0000-0000-0000-000000000010') = '$2b$12$user-credential-hash'
  AND identity.get_registration_password_hash('00000000-0000-0000-0000-000000000009') = '$2b$12$pending-request-hash'
  AND identity.get_verification_code_hash('00000000-0000-0000-0000-000000000121') = '$2b$12$user-otp-hash'
THEN 'OK' ELSE 'FAILED' END;

RESET ROLE;

DELETE FROM identity.user_verification_codes
 WHERE verification_code_id IN (
   '00000000-0000-0000-0000-000000000121',
   '00000000-0000-0000-0000-000000000122'
 );

DELETE FROM identity.user_credentials
 WHERE credential_id = '00000000-0000-0000-0000-000000000131';
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-012 acceptance verification failed: $result"
  }
}

function Test-UserVerificationCodesRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('identity.user_verification_codes') IS NULL
  AND to_regclass('identity.ix_user_verification_codes_user_id') IS NULL
  AND to_regclass('identity.ix_user_verification_codes_registration_request_id') IS NULL
  AND to_regclass('identity.ix_user_verification_codes_expires_at') IS NULL
  AND to_regprocedure('identity.get_user_password_hash(uuid)') IS NULL
  AND to_regprocedure('identity.get_registration_password_hash(uuid)') IS NULL
  AND to_regprocedure('identity.get_verification_code_hash(uuid)') IS NULL
  AND to_regprocedure('identity.get_user_session_refresh_token_hash(uuid)') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND to_regclass('identity.registration_requests') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-012 rollback isolation verification failed: $result"
  }
}

function Test-UserSessionsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000040', 'session.user', 'Session', 'User',
    'session.user@example.test', '3000000040', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO identity.user_sessions (
    session_id, user_id, refresh_token_hash, client_type, device_label,
    last_used_at, expires_at, created_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000141',
    '00000000-0000-0000-0000-000000000040', '$2b$12$mobile-refresh-token-hash',
    'MOBILE', 'Session test device', created_at_value,
    created_at_value + INTERVAL '2 months', created_at_value
  );

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000142',
      '00000000-0000-0000-0000-000000000040', '$2b$12$mobile-refresh-token-hash',
      'MOBILE', created_at_value, created_at_value + INTERVAL '2 months', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed a duplicate refresh-token hash.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000143',
      '00000000-0000-0000-0000-000000000099', '$2b$12$orphan-refresh-token-hash',
      'MOBILE', created_at_value, created_at_value + INTERVAL '2 months', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed a session without a user.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000144',
      '00000000-0000-0000-0000-000000000040', '$2b$12$invalid-client-refresh-token-hash',
      'WEB', created_at_value, created_at_value + INTERVAL '10 minutes', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed a client type outside its documented domain.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000145',
      '00000000-0000-0000-0000-000000000040', '$2b$12$invalid-expiry-refresh-token-hash',
      'ADMIN_WEB', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed an expiry that does not follow last use.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000146',
      '00000000-0000-0000-0000-000000000040', '$2b$12$invalid-last-use-refresh-token-hash',
      'ADMIN_WEB', created_at_value - INTERVAL '1 second',
      created_at_value + INTERVAL '10 minutes', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed last use before session creation.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO identity.user_sessions (
      session_id, user_id, refresh_token_hash, client_type,
      last_used_at, expires_at, revoked_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000147',
      '00000000-0000-0000-0000-000000000040', '$2b$12$invalid-revocation-refresh-token-hash',
      'MOBILE', created_at_value, created_at_value + INTERVAL '2 months',
      created_at_value - INTERVAL '1 second', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-013 allowed revocation before last use.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000041', 'session.cascade.user', 'Session', 'Cascade',
    'session.cascade.user@example.test', '3000000041', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO identity.user_sessions (
    session_id, user_id, refresh_token_hash, client_type,
    last_used_at, expires_at, created_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000148',
    '00000000-0000-0000-0000-000000000041', '$2b$12$cascade-refresh-token-hash',
    'MOBILE', created_at_value, created_at_value + INTERVAL '2 months', created_at_value
  );

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000041';

  IF EXISTS (
    SELECT 1 FROM identity.user_sessions
     WHERE session_id = '00000000-0000-0000-0000-000000000148'
  ) THEN
    RAISE EXCEPTION 'HU-DB-013 did not delete sessions when their user was deleted.';
  END IF;
END
$$;

SET ROLE alertamujer_app;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'identity.user_sessions', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'identity.user_sessions', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_sessions', 'SELECT')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_sessions', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'identity.user_sessions', 'TRUNCATE')
  AND has_column_privilege('alertamujer_app', 'identity.user_sessions', 'session_id', 'SELECT')
  AND NOT has_column_privilege('alertamujer_app', 'identity.user_sessions', 'refresh_token_hash', 'SELECT')
  AND NOT EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema = 'identity'
       AND table_name = 'user_sessions'
       AND column_name = 'refresh_token'
  )
THEN 'OK' ELSE 'FAILED' END;

RESET ROLE;

DELETE FROM identity.users
 WHERE user_id = '00000000-0000-0000-0000-000000000040';
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-013 acceptance verification failed: $result"
  }
}

function Test-UserSessionsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('identity.user_sessions') IS NULL
  AND to_regclass('identity.ix_user_sessions_user_id') IS NULL
  AND to_regclass('identity.ix_user_sessions_expires_at') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND to_regclass('identity.user_credentials') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-013 rollback isolation verification failed: $result"
  }
}

function Test-UserEmergencySettingsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000050', 'settings.user', 'Settings', 'User',
    'settings.user@example.test', '3000000050', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO profile.user_emergency_settings (
    setting_id, user_id, default_emergency_message, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000151',
    '00000000-0000-0000-0000-000000000050', 'Necesito ayuda.',
    created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO profile.user_emergency_settings (
      setting_id, user_id, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000152',
      '00000000-0000-0000-0000-000000000050', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-014 allowed more than one setting for a user.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE profile.user_emergency_settings
       SET default_emergency_message = '   '
     WHERE setting_id = '00000000-0000-0000-0000-000000000151';
    RAISE EXCEPTION 'HU-DB-014 allowed a blank SOS message.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE profile.user_emergency_settings
       SET default_emergency_message = repeat('x', 501)
     WHERE setting_id = '00000000-0000-0000-0000-000000000151';
    RAISE EXCEPTION 'HU-DB-014 allowed an SOS message longer than 500 characters.';
  EXCEPTION WHEN string_data_right_truncation THEN
    NULL;
  END;

  BEGIN
    UPDATE profile.user_emergency_settings
       SET updated_at = created_at - INTERVAL '1 second'
     WHERE setting_id = '00000000-0000-0000-0000-000000000151';
    RAISE EXCEPTION 'HU-DB-014 allowed updated_at before created_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO profile.user_emergency_settings (
      setting_id, user_id, default_emergency_message, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000155',
      '00000000-0000-0000-0000-000000000099', 'Orphan setting',
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-014 allowed a setting without a user.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000051', 'settings.cascade', 'Settings', 'Cascade',
    'settings.cascade@example.test', '3000000051', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO profile.user_emergency_settings (
    setting_id, user_id, default_emergency_message, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000156',
    '00000000-0000-0000-0000-000000000051', NULL, created_at_value, created_at_value
  );

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000051';

  IF EXISTS (
    SELECT 1
      FROM profile.user_emergency_settings
     WHERE setting_id = '00000000-0000-0000-0000-000000000156'
  ) THEN
    RAISE EXCEPTION 'HU-DB-014 did not delete settings when their user was deleted.';
  END IF;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'profile.user_emergency_settings', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'profile.user_emergency_settings', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'profile.user_emergency_settings', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'profile.user_emergency_settings', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'profile.user_emergency_settings', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;

DELETE FROM identity.users
 WHERE user_id = '00000000-0000-0000-0000-000000000050';
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-014 acceptance verification failed: $result"
  }
}

function Test-UserEmergencySettingsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('profile.user_emergency_settings') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-014 rollback isolation verification failed: $result"
  }
}

function Test-EmergencyContactsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000161', 'contact_owner_161', 'Contact', 'Owner', 'contact.owner.161@example.test', '3000000161', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000162', 'contact_user_162', 'Contact', 'User', 'contact.user.162@example.test', '3000000162', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000163', 'contact_user_163', 'Contact', 'User', 'contact.user.163@example.test', '3000000163', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000164', 'contact_user_164', 'Contact', 'User', 'contact.user.164@example.test', '3000000164', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000165', 'contact_user_165', 'Contact', 'User', 'contact.user.165@example.test', '3000000165', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000166', 'contact_owner_166', 'Contact', 'Owner', 'contact.owner.166@example.test', '3000000166', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000167', 'contact_user_167', 'Contact', 'User', 'contact.user.167@example.test', '3000000167', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value);

  INSERT INTO contacts.emergency_contacts (
    contact_id, owner_user_id, contact_user_id, relationship_status,
    expires_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000171',
    '00000000-0000-0000-0000-000000000161',
    '00000000-0000-0000-0000-000000000162', 'PENDING',
    created_at_value + INTERVAL '24 hours', created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000172',
      '00000000-0000-0000-0000-000000000162',
      '00000000-0000-0000-0000-000000000161', 'PENDING',
      created_at_value + INTERVAL '24 hours', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed the inverse duplicate contact pair.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000173',
      '00000000-0000-0000-0000-000000000161',
      '00000000-0000-0000-0000-000000000161', 'PENDING',
      created_at_value + INTERVAL '24 hours', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed a user to add itself as a contact.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000174',
      '00000000-0000-0000-0000-000000000163',
      '00000000-0000-0000-0000-000000000164', 'PENDING',
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed a pending contact without expiration.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000175',
      '00000000-0000-0000-0000-000000000163',
      '00000000-0000-0000-0000-000000000165', 'ACCEPTED',
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed a terminal contact without status_changed_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      status_changed_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000176',
      '00000000-0000-0000-0000-000000000164',
      '00000000-0000-0000-0000-000000000165', 'REJECTED',
      created_at_value - INTERVAL '1 second', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed status_changed_at before creation.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO contacts.emergency_contacts (
      contact_id, owner_user_id, contact_user_id, relationship_status,
      expires_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000177',
      '00000000-0000-0000-0000-000000000199',
      '00000000-0000-0000-0000-000000000161', 'PENDING',
      created_at_value + INTERVAL '24 hours', created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-015 allowed a contact without both registered users.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  INSERT INTO contacts.emergency_contacts (
    contact_id, owner_user_id, contact_user_id, relationship_status,
    status_changed_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000178',
    '00000000-0000-0000-0000-000000000166',
    '00000000-0000-0000-0000-000000000167', 'ACCEPTED',
    created_at_value, created_at_value, created_at_value
  );

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000166';

  IF EXISTS (
    SELECT 1
      FROM contacts.emergency_contacts
     WHERE contact_id = '00000000-0000-0000-0000-000000000178'
  ) OR NOT EXISTS (
    SELECT 1
      FROM identity.users
     WHERE user_id = '00000000-0000-0000-0000-000000000167'
  ) THEN
    RAISE EXCEPTION 'HU-DB-015 did not cascade only the deleted account contact links.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id IN (
     '00000000-0000-0000-0000-000000000161',
     '00000000-0000-0000-0000-000000000162',
     '00000000-0000-0000-0000-000000000163',
     '00000000-0000-0000-0000-000000000164',
     '00000000-0000-0000-0000-000000000165',
     '00000000-0000-0000-0000-000000000167'
   );
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'contacts.emergency_contacts', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'contacts.emergency_contacts', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'contacts.emergency_contacts', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'contacts.emergency_contacts', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'contacts.emergency_contacts', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-015 acceptance verification failed: $result"
  }
}

function Test-EmergencyContactsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('contacts.emergency_contacts') IS NULL
  AND to_regclass('contacts.ux_emergency_contacts_canonical_pair') IS NULL
  AND to_regclass('contacts.ix_emergency_contacts_owner_user_id') IS NULL
  AND to_regclass('contacts.ix_emergency_contacts_contact_user_id') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-015 rollback isolation verification failed: $result"
  }
}

function Test-UserDeviceTokensAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
  selected_device_token_id UUID;
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000181', 'device_owner_181', 'Device', 'Owner', 'device.owner.181@example.test', '3000000181', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000182', 'device_owner_182', 'Device', 'Owner', 'device.owner.182@example.test', '3000000182', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value);

  INSERT INTO notification.user_device_tokens (
    device_token_id, user_id, fcm_token, platform, device_label, is_active,
    last_seen_at, invalidated_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000191', '00000000-0000-0000-0000-000000000181', 'fcm-token-active-recent-191', 'ANDROID', 'Primary Android device', TRUE, created_at_value + INTERVAL '5 minutes', NULL, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000192', '00000000-0000-0000-0000-000000000181', 'fcm-token-inactive-192', 'ANDROID', 'Invalidated Android device', FALSE, created_at_value, created_at_value + INTERVAL '1 minute', created_at_value, created_at_value);

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000193', '00000000-0000-0000-0000-000000000182', 'fcm-token-active-recent-191', 'ANDROID', TRUE, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed a duplicate FCM token.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000194', '00000000-0000-0000-0000-000000000182', '   ', 'ANDROID', TRUE, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed a blank FCM token.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000195', '00000000-0000-0000-0000-000000000182', 'fcm-token-invalid-platform-195', 'IOS', TRUE, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed a platform outside the documented Android scope.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000196', '00000000-0000-0000-0000-000000000182', 'fcm-token-inactive-without-date-196', 'ANDROID', FALSE, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed an inactive token without invalidated_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, invalidated_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000197', '00000000-0000-0000-0000-000000000182', 'fcm-token-active-invalidated-197', 'ANDROID', TRUE, created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed an active token with an invalidation timestamp.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO notification.user_device_tokens (
      device_token_id, user_id, fcm_token, platform, is_active, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000198', '00000000-0000-0000-0000-000000000199', 'fcm-token-without-user-198', 'ANDROID', TRUE, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-016 allowed a token without a registered user.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  INSERT INTO notification.user_device_tokens (
    device_token_id, user_id, fcm_token, platform, is_active, last_seen_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000199', '00000000-0000-0000-0000-000000000182', 'fcm-token-cascade-199', 'ANDROID', TRUE, created_at_value, created_at_value, created_at_value
  );

  SELECT device_token_id
    INTO selected_device_token_id
    FROM notification.user_device_tokens
   WHERE user_id = '00000000-0000-0000-0000-000000000181'
     AND is_active
   ORDER BY last_seen_at DESC NULLS LAST
   LIMIT 1;

  IF selected_device_token_id <> '00000000-0000-0000-0000-000000000191'
    OR to_regclass('notification.ix_user_device_tokens_active_recent') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-016 does not support selecting the most recently seen active token.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000182';

  IF EXISTS (
    SELECT 1
      FROM notification.user_device_tokens
     WHERE device_token_id = '00000000-0000-0000-0000-000000000199'
  ) THEN
    RAISE EXCEPTION 'HU-DB-016 did not cascade the deleted user token.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000181';
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'notification.user_device_tokens', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'notification.user_device_tokens', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'notification.user_device_tokens', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'notification.user_device_tokens', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'notification.user_device_tokens', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-016 acceptance verification failed: $result"
  }
}

function Test-UserDeviceTokensRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('notification.user_device_tokens') IS NULL
  AND to_regclass('notification.uq_user_device_tokens_fcm_token') IS NULL
  AND to_regclass('notification.uq_user_device_tokens_id_user') IS NULL
  AND to_regclass('notification.ix_user_device_tokens_active_recent') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-016 rollback isolation verification failed: $result"
  }
}

function Test-EmergenciesAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000201', 'emergency_owner_201', 'Emergency', 'Owner', 'emergency.owner.201@example.test', '3000000201', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000202', 'emergency_owner_202', 'Emergency', 'Owner', 'emergency.owner.202@example.test', '3000000202', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value);

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, last_heartbeat_at,
    created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000211',
    '00000000-0000-0000-0000-000000000201', 'ACTIVE',
    'Necesito ayuda. Estoy en una emergencia.', created_at_value,
    created_at_value + INTERVAL '1 minute', created_at_value, created_at_value
  );

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000212',
      '00000000-0000-0000-0000-000000000201', 'IN_PROGRESS',
      'Second open SOS', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 allowed two open emergencies for one user.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000213',
      '00000000-0000-0000-0000-000000000202', 'OFFLINE',
      'Offline without previous operational status', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 allowed OFFLINE without ACTIVE or IN_PROGRESS as previous status.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000214',
      '00000000-0000-0000-0000-000000000202', 'FINALIZED',
      'Finalized without timestamp', created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 allowed FINALIZED without finalized_at.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, previous_operational_status, message_snapshot,
      started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000215',
      '00000000-0000-0000-0000-000000000202', 'ACTIVE', 'ACTIVE',
      'Operational status is only retained while offline', created_at_value,
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 retained previous operational status outside OFFLINE.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000216',
      '00000000-0000-0000-0000-000000000202', 'ACTIVE', '   ',
      created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 allowed a blank SOS message snapshot.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergencies (
      emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000217',
      '00000000-0000-0000-0000-000000000299', 'ACTIVE', 'SOS without owner',
      created_at_value, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-017 allowed an emergency without a registered owner.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, finalized_at,
    created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000218',
    '00000000-0000-0000-0000-000000000202', 'FINALIZED',
    'Finalized SOS', created_at_value, created_at_value + INTERVAL '1 minute',
    created_at_value, created_at_value
  );

  IF to_regclass('emergency.ux_emergencies_open_user') IS NULL
    OR to_regclass('emergency.ix_emergencies_user_id_started_at') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-017 did not create the documented emergency indexes.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000201';

  IF EXISTS (
    SELECT 1
      FROM emergency.emergencies
     WHERE emergency_id = '00000000-0000-0000-0000-000000000211'
  ) THEN
    RAISE EXCEPTION 'HU-DB-017 did not cascade the deleted owner emergency.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000202';
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'emergency.emergencies', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergencies', 'INSERT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergencies', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergencies', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergencies', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-017 acceptance verification failed: $result"
  }
}

function Test-EmergenciesRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('emergency.emergencies') IS NULL
  AND to_regclass('emergency.ux_emergencies_open_user') IS NULL
  AND to_regclass('emergency.ix_emergencies_user_id_started_at') IS NULL
  AND to_regclass('identity.users') IS NOT NULL
  AND (SELECT count(*) FROM configuration.system_configuration) = 1
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-017 rollback isolation verification failed: $result"
  }
}

function Test-EmergencyStatusHistoryAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
  current_status_value VARCHAR(11);
  latest_history_status VARCHAR(11);
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000221', 'history_owner_221', 'History', 'Owner', 'history.owner.221@example.test', '3000000221', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000222', 'history_owner_222', 'History', 'Invalid', 'history.invalid.222@example.test', '3000000222', 'USER', 'ENABLED', 'SELF_REGISTERED', created_at_value, created_at_value, created_at_value);

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000231', '00000000-0000-0000-0000-000000000221', 'ACTIVE', 'History SOS', created_at_value, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000232', '00000000-0000-0000-0000-000000000222', 'ACTIVE', 'Invalid initial history SOS', created_at_value, created_at_value, created_at_value);

  INSERT INTO emergency.emergency_status_history (
    emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
    occurred_at, created_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000241',
    '00000000-0000-0000-0000-000000000231', 1, NULL, 'ACTIVE',
    created_at_value, created_at_value
  );

  UPDATE emergency.emergencies
     SET status = 'IN_PROGRESS', updated_at = created_at_value + INTERVAL '1 minute'
   WHERE emergency_id = '00000000-0000-0000-0000-000000000231';

  INSERT INTO emergency.emergency_status_history (
    emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
    actor_user_id, cause, occurred_at, created_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000242',
    '00000000-0000-0000-0000-000000000231', 2, 'ACTIVE', 'IN_PROGRESS',
    '00000000-0000-0000-0000-000000000221', 'Administrative attention started',
    created_at_value + INTERVAL '1 minute', created_at_value + INTERVAL '1 minute'
  );

  SELECT status
    INTO current_status_value
    FROM emergency.emergencies
   WHERE emergency_id = '00000000-0000-0000-0000-000000000231';

  SELECT new_status
    INTO latest_history_status
    FROM emergency.emergency_status_history
   WHERE emergency_id = '00000000-0000-0000-0000-000000000231'
   ORDER BY sequence_no DESC
   LIMIT 1;

  IF current_status_value <> 'IN_PROGRESS'
    OR latest_history_status <> current_status_value THEN
    RAISE EXCEPTION 'HU-DB-018 did not support a consistent state and history transaction.';
  END IF;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000243',
      '00000000-0000-0000-0000-000000000231', 2, 'ACTIVE', 'IN_PROGRESS',
      created_at_value + INTERVAL '2 minutes', created_at_value + INTERVAL '2 minutes'
    );
    RAISE EXCEPTION 'HU-DB-018 allowed a duplicate history sequence for one emergency.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000244',
      '00000000-0000-0000-0000-000000000232', 1, NULL, 'IN_PROGRESS',
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-018 allowed an invalid initial history record.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000245',
      '00000000-0000-0000-0000-000000000231', 3, NULL, 'OFFLINE',
      created_at_value + INTERVAL '2 minutes', created_at_value + INTERVAL '2 minutes'
    );
    RAISE EXCEPTION 'HU-DB-018 allowed a non-initial history record without a previous status.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000246',
      '00000000-0000-0000-0000-000000000299', 1, NULL, 'ACTIVE',
      created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-018 allowed history without an emergency.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      actor_user_id, occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000247',
      '00000000-0000-0000-0000-000000000231', 3, 'IN_PROGRESS', 'OFFLINE',
      '00000000-0000-0000-0000-000000000299', created_at_value + INTERVAL '2 minutes', created_at_value + INTERVAL '2 minutes'
    );
    RAISE EXCEPTION 'HU-DB-018 allowed an unknown history actor.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_status_history (
      emergency_status_history_id, emergency_id, sequence_no, previous_status, new_status,
      cause, occurred_at, created_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000248',
      '00000000-0000-0000-0000-000000000231', 3, 'IN_PROGRESS', 'OFFLINE',
      '   ', created_at_value + INTERVAL '2 minutes', created_at_value + INTERVAL '2 minutes'
    );
    RAISE EXCEPTION 'HU-DB-018 allowed a blank history cause.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  IF to_regclass('emergency.ix_emergency_status_history_emergency_occurred_sequence') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-018 did not create the documented history index.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000221';

  IF EXISTS (
    SELECT 1
      FROM emergency.emergency_status_history
     WHERE emergency_id = '00000000-0000-0000-0000-000000000231'
  ) THEN
    RAISE EXCEPTION 'HU-DB-018 did not cascade deleted emergency history.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000222';
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'emergency.emergency_status_history', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergency_status_history', 'INSERT')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_status_history', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_status_history', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_status_history', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-018 acceptance verification failed: $result"
  }
}

function Test-EmergencyStatusHistoryRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('emergency.emergency_status_history') IS NULL
  AND to_regclass('emergency.ix_emergency_status_history_emergency_occurred_sequence') IS NULL
  AND to_regclass('emergency.emergencies') IS NOT NULL
  AND to_regclass('identity.users') IS NOT NULL
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-018 rollback isolation verification failed: $result"
  }
}

function Test-EmergencyLocationsAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000251', 'location_owner_251', 'Location', 'Owner',
    'location.owner.251@example.test', '3000000251', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000261', '00000000-0000-0000-0000-000000000251',
    'ACTIVE', 'Location SOS', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergency_locations (
    location_id, emergency_id, latitude, longitude, accuracy_meters, captured_at, received_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000271', '00000000-0000-0000-0000-000000000261',
     4.609710, -74.081750, 3.5, created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000261',
     -90.000000, 180.000000, NULL, created_at_value + INTERVAL '1 minute', created_at_value + INTERVAL '1 minute');

  BEGIN
    INSERT INTO emergency.emergency_locations (
      location_id, emergency_id, latitude, longitude, captured_at, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000273', '00000000-0000-0000-0000-000000000261',
      90.000001, 0, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-019 allowed a latitude outside the documented range.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_locations (
      location_id, emergency_id, latitude, longitude, captured_at, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000274', '00000000-0000-0000-0000-000000000261',
      0, -180.000001, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-019 allowed a longitude outside the documented range.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_locations (
      location_id, emergency_id, latitude, longitude, accuracy_meters, captured_at, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000275', '00000000-0000-0000-0000-000000000261',
      0, 0, -0.1, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-019 allowed negative location accuracy.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_locations (
      location_id, emergency_id, latitude, longitude, captured_at, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000276', '00000000-0000-0000-0000-000000000299',
      0, 0, created_at_value, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-019 allowed a location without an emergency.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  IF to_regclass('emergency.ix_emergency_locations_emergency_received_at') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-019 did not create the documented latest-location index.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000251';

  IF EXISTS (
    SELECT 1
      FROM emergency.emergency_locations
     WHERE emergency_id = '00000000-0000-0000-0000-000000000261'
  ) THEN
    RAISE EXCEPTION 'HU-DB-019 did not cascade deleted emergency locations.';
  END IF;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'emergency.emergency_locations', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergency_locations', 'INSERT')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_locations', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_locations', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_locations', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-019 acceptance verification failed: $result"
  }
}

function Test-EmergencyLocationsRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('emergency.emergency_locations') IS NULL
  AND to_regclass('emergency.ix_emergency_locations_emergency_received_at') IS NULL
  AND to_regclass('emergency.emergencies') IS NOT NULL
  AND to_regclass('identity.users') IS NOT NULL
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-019 rollback isolation verification failed: $result"
  }
}

function Test-EmergencyEvidencesAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000281', 'evidence_owner_281', 'Evidence', 'Owner',
    'evidence.owner.281@example.test', '3000000281', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000291', '00000000-0000-0000-0000-000000000281',
    'ACTIVE', 'Evidence SOS', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergency_evidences (
    evidence_id, emergency_id, evidence_sequence, file_reference, original_file_name,
    mime_type, original_mime_type, file_size_bytes, captured_at, received_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000291',
     1, 'evidence-301', 'capture-301.jpg', 'image/webp', 'image/jpeg', 1048576,
     created_at_value, created_at_value),
    ('00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000291',
     10, 'evidence-302', NULL, 'image/webp', NULL, 1,
     NULL, created_at_value + INTERVAL '1 minute');

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000303', '00000000-0000-0000-0000-000000000291',
      1, 'evidence-303', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed duplicate evidence sequence for one emergency.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000291',
      2, 'evidence-301', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed a reused internal file reference.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000305', '00000000-0000-0000-0000-000000000291',
      0, 'evidence-305', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed an evidence sequence below the documented range.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000306', '00000000-0000-0000-0000-000000000291',
      11, 'evidence-306', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed an evidence sequence above the documented range.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000307', '00000000-0000-0000-0000-000000000291',
      2, 'evidence-307', 'image/jpeg', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed a final MIME type other than image/webp.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000308', '00000000-0000-0000-0000-000000000291',
      2, 'evidence-308', 'image/webp', 0, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed an empty final evidence file.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000309', '00000000-0000-0000-0000-000000000291',
      2, 'evidence-309', 'image/webp', 1048577, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed a final evidence file above the documented size.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000310', '00000000-0000-0000-0000-000000000291',
      2, '   ', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed a blank internal file reference.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_evidences (
      evidence_id, emergency_id, evidence_sequence, file_reference, mime_type,
      file_size_bytes, received_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000399',
      1, 'evidence-311', 'image/webp', 10, created_at_value
    );
    RAISE EXCEPTION 'HU-DB-020 allowed evidence without an emergency.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  IF to_regclass('emergency.ix_emergency_evidences_emergency_received_at') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-020 did not create the documented evidence receipt index.';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema = 'emergency'
       AND table_name = 'emergency_evidences'
       AND (column_name = 'user_id' OR data_type = 'bytea')
  ) THEN
    RAISE EXCEPTION 'HU-DB-020 persisted a redundant owner or binary evidence data.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000281';

  IF EXISTS (
    SELECT 1
      FROM emergency.emergency_evidences
     WHERE emergency_id = '00000000-0000-0000-0000-000000000291'
  ) THEN
    RAISE EXCEPTION 'HU-DB-020 did not cascade deleted emergency evidence metadata.';
  END IF;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'emergency.emergency_evidences', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergency_evidences', 'INSERT')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_evidences', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_evidences', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_evidences', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-020 acceptance verification failed: $result"
  }
}

function Test-EmergencyEvidencesRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('emergency.emergency_evidences') IS NULL
  AND to_regclass('emergency.ix_emergency_evidences_emergency_received_at') IS NULL
  AND to_regclass('emergency.emergencies') IS NOT NULL
  AND to_regclass('identity.users') IS NOT NULL
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-020 rollback isolation verification failed: $result"
  }
}

function Test-EmergencyChatMessagesAcceptance {
  $sql = @'
DO $$
DECLARE
  created_at_value CONSTANT TIMESTAMPTZ := '2026-10-03 00:00:00+00';
  ordered_contents TEXT[];
BEGIN
  INSERT INTO identity.users (
    user_id, username, first_names, last_names, email, phone, role,
    account_status, account_origin, accepted_terms_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000321', 'chat_owner_321', 'Chat', 'Owner',
    'chat.owner.321@example.test', '3000000321', 'USER', 'ENABLED',
    'SELF_REGISTERED', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergencies (
    emergency_id, user_id, status, message_snapshot, started_at, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000331', '00000000-0000-0000-0000-000000000321',
    'ACTIVE', 'Chat SOS', created_at_value, created_at_value, created_at_value
  );

  INSERT INTO emergency.emergency_chat_messages (
    client_message_id, emergency_id, sender_user_id, content, sent_at
  ) VALUES
    ('00000000-0000-0000-0000-000000000341', '00000000-0000-0000-0000-000000000331',
     '00000000-0000-0000-0000-000000000321', 'first', created_at_value),
    ('00000000-0000-0000-0000-000000000342', '00000000-0000-0000-0000-000000000331',
     '00000000-0000-0000-0000-000000000321', 'latest-a', created_at_value + INTERVAL '1 minute'),
    ('00000000-0000-0000-0000-000000000343', '00000000-0000-0000-0000-000000000331',
     '00000000-0000-0000-0000-000000000321', 'latest-b', created_at_value + INTERVAL '1 minute');

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, sender_user_id, content, sent_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000341', '00000000-0000-0000-0000-000000000331',
      '00000000-0000-0000-0000-000000000321', 'duplicate retry', created_at_value
    );
    RAISE EXCEPTION 'HU-DB-021 allowed a duplicate client message identifier for one emergency.';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, sender_user_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000344', '00000000-0000-0000-0000-000000000331',
      '00000000-0000-0000-0000-000000000321', '   '
    );
    RAISE EXCEPTION 'HU-DB-021 allowed blank chat content.';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, sender_user_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000345', '00000000-0000-0000-0000-000000000331',
      '00000000-0000-0000-0000-000000000321', repeat('x', 501)
    );
    RAISE EXCEPTION 'HU-DB-021 allowed chat content above 500 characters.';
  EXCEPTION WHEN string_data_right_truncation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, sender_user_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000346', '00000000-0000-0000-0000-000000000321', 'no emergency'
    );
    RAISE EXCEPTION 'HU-DB-021 allowed a message without an emergency.';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000347', '00000000-0000-0000-0000-000000000331', 'no sender'
    );
    RAISE EXCEPTION 'HU-DB-021 allowed a message without a sender.';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, sender_user_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000348', '00000000-0000-0000-0000-000000000399',
      '00000000-0000-0000-0000-000000000321', 'unknown emergency'
    );
    RAISE EXCEPTION 'HU-DB-021 allowed an unknown emergency.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO emergency.emergency_chat_messages (
      client_message_id, emergency_id, sender_user_id, content
    ) VALUES (
      '00000000-0000-0000-0000-000000000349', '00000000-0000-0000-0000-000000000331',
      '00000000-0000-0000-0000-000000000399', 'unknown sender'
    );
    RAISE EXCEPTION 'HU-DB-021 allowed an unknown sender.';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  IF (SELECT count(*) FROM emergency.emergency_chat_messages
      WHERE emergency_id = '00000000-0000-0000-0000-000000000331'
        AND client_message_id = '00000000-0000-0000-0000-000000000341') <> 1 THEN
    RAISE EXCEPTION 'HU-DB-021 did not preserve one message per emergency/client identifier.';
  END IF;

  SELECT array_agg(content ORDER BY sent_at DESC, chat_message_id DESC)
    INTO ordered_contents
    FROM emergency.emergency_chat_messages
   WHERE emergency_id = '00000000-0000-0000-0000-000000000331';

  IF ordered_contents <> ARRAY['latest-b', 'latest-a', 'first'] THEN
    RAISE EXCEPTION 'HU-DB-021 did not preserve the documented sent-at and stable-id order.';
  END IF;

  IF to_regclass('emergency.ix_emergency_chat_messages_emergency_sent_at') IS NULL THEN
    RAISE EXCEPTION 'HU-DB-021 did not create the documented chat retrieval index.';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM information_schema.columns
     WHERE table_schema = 'emergency'
       AND table_name = 'emergency_chat_messages'
       AND column_name IN ('sender_role_snapshot', 'sender_role', 'status')
  ) THEN
    RAISE EXCEPTION 'HU-DB-021 persisted a sender role or visual-state snapshot.';
  END IF;

  DELETE FROM identity.users
   WHERE user_id = '00000000-0000-0000-0000-000000000321';

  IF EXISTS (
    SELECT 1
      FROM emergency.emergency_chat_messages
     WHERE emergency_id = '00000000-0000-0000-0000-000000000331'
  ) THEN
    RAISE EXCEPTION 'HU-DB-021 did not cascade deleted emergency chat messages.';
  END IF;
END
$$;

SELECT CASE WHEN
  has_table_privilege('alertamujer_app', 'emergency.emergency_chat_messages', 'SELECT')
  AND has_table_privilege('alertamujer_app', 'emergency.emergency_chat_messages', 'INSERT')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_chat_messages', 'UPDATE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_chat_messages', 'DELETE')
  AND NOT has_table_privilege('alertamujer_app', 'emergency.emergency_chat_messages', 'TRUNCATE')
THEN 'OK' ELSE 'FAILED' END;
'@

  $result = Invoke-PostgresScalar -Sql $sql
  if ($result -ne 'OK') {
    throw "HU-DB-021 acceptance verification failed: $result"
  }
}

function Test-EmergencyChatMessagesRollback {
  $result = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  to_regclass('emergency.emergency_chat_messages') IS NULL
  AND to_regclass('emergency.ix_emergency_chat_messages_emergency_sent_at') IS NULL
  AND to_regclass('emergency.emergencies') IS NOT NULL
  AND to_regclass('identity.users') IS NOT NULL
THEN 'OK' ELSE 'FAILED' END;
'@

  if ($result -ne 'OK') {
    throw "HU-DB-021 rollback isolation verification failed: $result"
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
  Invoke-Liquibase -Phase 'update (baseline without HU-DB-009 through HU-DB-021)' -Command @('update', '--label-filter=!hu-db-009 AND !hu-db-010 AND !hu-db-011 AND !hu-db-012 AND !hu-db-013 AND !hu-db-014 AND !hu-db-015 AND !hu-db-016 AND !hu-db-017 AND !hu-db-018 AND !hu-db-019 AND !hu-db-020 AND !hu-db-021')
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
  Invoke-Liquibase -Phase 'update (restore HU-DB-010)' -Command @('update', '--label-filter=hu-db-010')
  Test-UsersAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-014)' -Command @('update', '--label-filter=hu-db-014')
  Test-UserEmergencySettingsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-014)' -Command @('rollback-count', '--count=2')
  Test-UserEmergencySettingsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-014)' -Command @('update', '--label-filter=hu-db-014')
  Test-UserEmergencySettingsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-011)' -Command @('update', '--label-filter=hu-db-011')
  Test-UserCredentialsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-011)' -Command @('rollback-count', '--count=2')
  Test-UserCredentialsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-011)' -Command @('update', '--label-filter=hu-db-011')
  Test-UserCredentialsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-013)' -Command @('update', '--label-filter=hu-db-013')
  Test-UserSessionsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-013)' -Command @('rollback-count', '--count=3')
  Test-UserSessionsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-013)' -Command @('update', '--label-filter=hu-db-013')
  Test-UserSessionsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-012)' -Command @('update', '--label-filter=hu-db-012')
  Test-UserVerificationCodesAcceptance
  $sessionHashFunctionGrant = Invoke-PostgresScalar -Sql @'
SELECT CASE WHEN
  has_function_privilege('alertamujer_app', 'identity.get_user_session_refresh_token_hash(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('public', 'identity.get_user_session_refresh_token_hash(uuid)', 'EXECUTE')
THEN 'OK' ELSE 'FAILED' END;
'@
  if ($sessionHashFunctionGrant -ne 'OK') {
    throw 'HU-DB-012 session refresh-token hash function access verification failed.'
  }
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-012)' -Command @('rollback-count', '--count=5')
  Test-UserVerificationCodesRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-012)' -Command @('update', '--label-filter=hu-db-012')
  Test-UserVerificationCodesAcceptance
  Test-UserSessionsAcceptance
  Test-UserEmergencySettingsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-015)' -Command @('update', '--label-filter=hu-db-015')
  Test-EmergencyContactsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-015)' -Command @('rollback-count', '--count=3')
  Test-EmergencyContactsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-015)' -Command @('update', '--label-filter=hu-db-015')
  Test-EmergencyContactsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-016)' -Command @('update', '--label-filter=hu-db-016')
  Test-UserDeviceTokensAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-016)' -Command @('rollback-count', '--count=3')
  Test-UserDeviceTokensRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-016)' -Command @('update', '--label-filter=hu-db-016')
  Test-UserDeviceTokensAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-017)' -Command @('update', '--label-filter=hu-db-017')
  Test-EmergenciesAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-017)' -Command @('rollback-count', '--count=3')
  Test-EmergenciesRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-017)' -Command @('update', '--label-filter=hu-db-017')
  Test-EmergenciesAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-018)' -Command @('update', '--label-filter=hu-db-018')
  Test-EmergencyStatusHistoryAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-018)' -Command @('rollback-count', '--count=3')
  Test-EmergencyStatusHistoryRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-018)' -Command @('update', '--label-filter=hu-db-018')
  Test-EmergencyStatusHistoryAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-019)' -Command @('update', '--label-filter=hu-db-019')
  Test-EmergencyLocationsAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-019)' -Command @('rollback-count', '--count=3')
  Test-EmergencyLocationsRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-019)' -Command @('update', '--label-filter=hu-db-019')
  Test-EmergencyLocationsAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-020)' -Command @('update', '--label-filter=hu-db-020')
  Test-EmergencyEvidencesAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-020)' -Command @('rollback-count', '--count=3')
  Test-EmergencyEvidencesRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-020)' -Command @('update', '--label-filter=hu-db-020')
  Test-EmergencyEvidencesAcceptance
  Invoke-Liquibase -Phase 'update (HU-DB-021)' -Command @('update', '--label-filter=hu-db-021')
  Test-EmergencyChatMessagesAcceptance
  Invoke-Liquibase -Phase 'rollback-count (HU-DB-021)' -Command @('rollback-count', '--count=3')
  Test-EmergencyChatMessagesRollback
  Invoke-Liquibase -Phase 'update (restore HU-DB-021)' -Command @('update', '--label-filter=hu-db-021')
  Test-EmergencyChatMessagesAcceptance
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
