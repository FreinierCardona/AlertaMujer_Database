[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sql = @'
SELECT CASE WHEN
  pg_has_role('alertamujer_migrator', 'alertamujer_owner', 'member')
  AND has_schema_privilege('alertamujer_app', 'identity', 'USAGE')
  AND NOT has_schema_privilege('alertamujer_app', 'identity', 'CREATE')
  AND NOT has_schema_privilege('alertamujer_app', 'public', 'CREATE')
  AND NOT has_database_privilege('alertamujer_app', current_database(), 'CREATE')
  AND NOT EXISTS (
    SELECT 1
      FROM pg_namespace AS schema_namespace
      CROSS JOIN LATERAL aclexplode(COALESCE(schema_namespace.nspacl, acldefault('n', schema_namespace.nspowner))) AS privilege
     WHERE schema_namespace.nspname = 'public'
       AND privilege.grantee = 0
       AND privilege.privilege_type = 'CREATE'
  )
THEN 'OK' ELSE 'FAILED' END;
'@

$encodedSql = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sql))
$probe = "printf '%s' '$encodedSql' | base64 -d | PGPORT=`"`$POSTGRES_CONTAINER_PORT`" psql -X -v ON_ERROR_STOP=1 -U `"`$POSTGRES_USER`" -d `"`$POSTGRES_DB`" -At"
$output = & docker compose exec --no-TTY postgres sh -c $probe
if ($LASTEXITCODE -ne 0) {
  throw "Technical role verification failed with exit code $LASTEXITCODE."
}

$result = ($output | Out-String).Trim()

if ($result -ne 'OK') {
  throw "Technical role matrix failed: $result"
}

Write-Host 'Technical roles verified: migrator membership, application USAGE, and no application/PUBLIC DDL.'
