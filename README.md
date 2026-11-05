# AlertaMujer Database

Repositorio de la base de datos PostgreSQL de AlertaMujer. Contiene la infraestructura local Docker, los changesets Liquibase, los rollbacks y las verificaciones de release. No contiene datos reales ni código del backend.

## Requisitos

- Docker Desktop con Docker Compose v2.
- PowerShell para ejecutar los scripts `.ps1`.
- Puerto local `5434` disponible, salvo que se cambie `POSTGRES_PORT` en `.env`.

## Inicio rápido

Desde la raíz del repositorio:

```powershell
Copy-Item .env.example .env
# Edite .env y reemplace cada valor CAMBIAR por una contraseña local segura.

# Inicia PostgreSQL y aplica los changesets pendientes con Liquibase.
docker compose up
```

Para dejar los servicios en segundo plano:

```powershell
docker compose up -d
docker compose logs liquibase
```

PostgreSQL queda disponible desde el equipo en `127.0.0.1:5434` y dentro de Docker en `postgres:5433` por defecto. Liquibase espera el healthcheck de PostgreSQL, ejecuta `update` y termina.

Detener sin borrar datos:

```powershell
docker compose down
```

Reiniciar la base local desde cero:

```powershell
docker compose down --volumes
```

El segundo comando elimina el volumen local y no se puede deshacer.

## Estructura

```text
AlertaMujer_Database/
├── 01_ddl/          # Extensiones, schemas, tablas, restricciones, alteraciones e índices.
├── 02_dml/          # Datos técnicos controlados, seeds y ajustes de datos.
├── 03_dcl/          # Roles, grants y políticas de acceso.
├── 04_tcl/          # Bloques transaccionales y etiquetas de release.
├── 05_rollbacks/    # Rollback de cada changeset, con estructura espejo.
├── changelog/       # changelog-master.yaml y cadena principal de Liquibase.
├── docker/initdb/   # Inicialización y reconciliación de roles PostgreSQL.
├── scripts/         # Arranque, verificaciones y prueba aislada de release.
├── docker-compose.yml
├── Dockerfile
├── liquibase.properties
└── .env.example
```

Los archivos `0000changelog.yaml` encadenan los changesets de cada módulo. Todo cambio de esquema, dato controlado o privilegio debe incluir su SQL de avance, rollback, referencia desde el changelog y etiqueta de la HU correspondiente. Los changesets aplicados son inmutables: una corrección se agrega como migration nueva.

## Roles operativos

| Rol | Uso | Alcance |
| --- | --- | --- |
| `alertamujer_owner` | Propietario técnico sin inicio de sesión. | Es dueño de `public` y de los schemas funcionales. No lo usa el backend. |
| `alertamujer_migrator` | Usuario de Liquibase. | Inicia sesión, asume `alertamujer_owner` y ejecuta migrations. No es superusuario ni crea bases de datos. |
| `alertamujer_app` | Usuario del backend. | Tiene solo `CONNECT`, `USAGE` y DML explícito. No recibe DDL, `TRUNCATE` ni administración de roles. |

`alertamujer_app` puede eliminar únicamente `identity.registration_requests`, `identity.user_verification_codes` e `identity.users`, para purgas técnicas y el borrado terminal de cuenta. No recibe `DELETE` sobre emergencias, evidencias, sesiones, notificaciones, mensajes ni auditoría. La autorización del flujo sigue siendo responsabilidad del backend.

Las credenciales viven exclusivamente en `.env`. Los nombres de aplicación y migración son fijos: `alertamujer_app` y `alertamujer_migrator`.

## Docker y Liquibase

Comprobar la configuración de Compose:

```powershell
docker compose config --quiet
```

Operar Liquibase manualmente:

```powershell
# Valida changelogs, rutas y referencias sin cambiar la base.
docker compose run --rm liquibase validate

# Muestra los changesets pendientes.
docker compose run --rm liquibase status --verbose

# Muestra el SQL que se ejecutaría, sin aplicarlo.
docker compose run --rm liquibase update-sql

# Aplica los changesets pendientes.
docker compose run --rm liquibase update

# Consulta el historial aplicado.
docker compose run --rm liquibase history
```

Liquibase siempre se conecta con `alertamujer_migrator`; el backend nunca ejecuta migrations. Para una base ya creada antes de cambiar las credenciales de `.env`, ejecute primero la reconciliación de roles.

## Scripts

| Archivo | Ejecución | Función |
| --- | --- | --- |
| `scripts/start-postgres.ps1` | `./scripts/start-postgres.ps1` | Valida Compose, inicia solo PostgreSQL, espera su healthcheck y muestra el endpoint publicado. No ejecuta Liquibase. |
| `scripts/verify-postgres.ps1` | `./scripts/verify-postgres.ps1` | Inicia PostgreSQL si es necesario; valida conexión con `alertamujer_app`, UTF-8, UTC y persistencia del volumen tras reiniciar el contenedor. |
| `scripts/reconcile-technical-roles.ps1` | `./scripts/reconcile-technical-roles.ps1` | Aplica al volumen existente las credenciales y propiedad técnica definidas en `.env`. Úselo después de cambiar contraseñas locales. |
| `scripts/verify-technical-roles.ps1` | `./scripts/verify-technical-roles.ps1` | Comprueba membresía del migrador en el owner, `USAGE` de la aplicación y ausencia de privilegios DDL para aplicación y `PUBLIC`. |
| `scripts/test-release.ps1` | `./scripts/test-release.ps1 -ReleaseTag alertamujer-db-vX.Y.Z` | Crea una infraestructura aislada, ejecuta validación, update, pruebas de aceptación, rollback/reaplicación, fingerprint, tag y comprobación de locks. Elimina sus recursos al terminar. Use `-KeepEnvironment` solo para diagnosticar un fallo. |
| `docker/initdb/10-create-application-role.sh` | No se ejecuta manualmente desde el host. | Se ejecuta al inicializar PostgreSQL y desde el script de reconciliación. Valida los nombres fijos de roles, crea o actualiza credenciales, configura owner/migrator y otorga conectividad a la aplicación. |

Ejemplo de validación de release:

```powershell
./scripts/test-release.ps1 -ReleaseTag alertamujer-db-v1.0.24
```

Una release se considera validada únicamente cuando el script termina con `Release validation passed`.

## Convenciones de trabajo

1. Cree una rama `feat/hu-db-NNN-dev` desde `develop` limpio.
2. Agregue migration y rollback sin modificar changesets ya aplicados.
3. Actualice el changelog y la prueba de release cuando cambie una regla persistente o un privilegio.
4. Ejecute `docker compose run --rm liquibase validate` y `./scripts/test-release.ps1`.
5. Confirme los cambios y publique la rama; `develop` solo recibe cambios integrados.
