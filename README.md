# AlertaMujer Database

Repositorio de PostgreSQL y Liquibase de AlertaMujer. Centraliza la infraestructura local y el versionamiento de los changesets entregados para las HUs de base de datos; no contiene datos reales.

## Estructura del repositorio

```text
AlertaMujer_Database/
├── 01_ddl/              # Estructuras de base de datos.
├── 02_dml/              # Datos controlados.
├── 03_dcl/              # Roles, permisos y políticas.
├── 04_tcl/              # Operaciones transaccionales y versiones.
├── 05_rollbacks/        # Reversiones de futuros changesets.
├── changelog/           # Punto de entrada de Liquibase.
├── docker/              # Inicialización técnica de PostgreSQL.
├── scripts/             # Operación y verificación local.
├── Dockerfile
├── docker-compose.yml
├── liquibase.properties
└── .env.example
```

## Estructura de changelogs

```text
changelog/
└── changelog-master.yaml
    ├── ../01_ddl/changelog.yaml
    │   └── 00_extensions … 10_indexes/0000changelog.yaml
    ├── ../02_dml/changelog.yaml
    │   └── 00_inserts … 04_patches/0000changelog.yaml
    ├── ../03_dcl/changelog.yaml
    │   └── 00_roles … 02_policies/0000changelog.yaml
    └── ../04_tcl/changelog.yaml
        └── 00_transaction_blocks … 02_release_tags/0000changelog.yaml
```

Los changelogs internos son el lugar exclusivo para registrar changesets, respetando el orden DDL, DML, DCL y TCL.

## Roles técnicos y privilegios

| Rol | Uso | Privilegios efectivos |
| --- | --- | --- |
| `POSTGRES_USER` | Inicialización y reconciliación administrativa del contenedor. | Administra el clúster y los roles técnicos; no lo usa el backend ni Liquibase durante las migraciones ordinarias. |
| `alertamujer_owner` | Propietario técnico sin inicio de sesión. | Posee `public` y los schemas funcionales; puede crear objetos en la base y gestionar los metadatos de Liquibase. |
| `alertamujer_migrator` | Liquibase. | Inicia sesión, pertenece a `alertamujer_owner` y opera como owner al ejecutar migrations. Puede administrar roles técnicos, pero no es superusuario ni puede crear bases. |
| `alertamujer_app` | Backend de AlertaMujer. | Puede conectarse y usar los schemas funcionales. Los objetos futuros reciben solo el DML mínimo: lectura en `configuration`; lectura/inserción/actualización en `identity`, `profile`, `contacts` y `notification`; lectura/inserción en `emergency` y `audit`. No recibe DDL, `TRUNCATE` ni privilegios predeterminados de `DELETE`. |

En `identity.registration_requests`, `alertamujer_app` inserta y actualiza el flujo temporal, pero su `SELECT` es por columnas y excluye `password_hash`.

En `identity.users`, `alertamujer_app` tiene `SELECT`, `INSERT` y `UPDATE` para el ciclo de vida de cuentas; no recibe `DELETE`, `TRUNCATE` ni permisos de administración.

Las tablas de credenciales, solicitudes de registro y OTP no exponen hashes mediante `SELECT` al rol de aplicación. Para las verificaciones de autenticación de las HUs implementadas, `alertamujer_app` solo puede ejecutar `identity.get_user_password_hash(uuid)`, `identity.get_registration_password_hash(uuid)` e `identity.get_verification_code_hash(uuid)`. Cada función recibe un identificador y devuelve exclusivamente el hash asociado; el backend conserva la autorización del flujo y la comparación segura.

Las contraseñas no se versionan. `POSTGRES_USER`/`POSTGRES_PASSWORD`, `APP_DB_USER`/`APP_DB_PASSWORD` y `MIGRATOR_DB_USER`/`MIGRATOR_DB_PASSWORD` se leen de `.env`. Los nombres de aplicación y migración están fijados como `alertamujer_app` y `alertamujer_migrator`; el script rechaza otros nombres. En un volumen existente, cambiar una contraseña en `.env` requiere ejecutar `./scripts/reconcile-technical-roles.ps1` para aplicarla en PostgreSQL; editar `.env` por sí solo no rota credenciales ya persistidas.

## Configuración operativa global

`configuration.system_configuration` contiene la única configuración global aprobada para SOS, heartbeat, evidencia, chat y OTP. La fila inicial usa los límites vigentes del proyecto; su PK y `CHECK (configuration_id = 1)` impiden una segunda configuración, todos los límites son positivos y el timeout de desconexión debe superar el intervalo de heartbeat.

El backend consulta estos valores y conserva los hechos aplicados en sus entidades operativas futuras. `alertamujer_app` tiene únicamente `SELECT` sobre esta tabla; los cambios se entregan mediante un nuevo changeset con su rollback, nunca mediante una pantalla administrativa ni Compose.

## Inicio local

Requiere Docker Desktop y el puerto `5434` disponible.

```powershell
Copy-Item .env.example .env
# Edite .env y defina POSTGRES_PASSWORD, APP_DB_PASSWORD y MIGRATOR_DB_PASSWORD.

# PostgreSQL y Liquibase; Liquibase aplica los changesets pendientes.
docker compose up

# La misma operación en segundo plano.
docker compose up -d
```

PostgreSQL inicia primero. Cuando su `healthcheck` es satisfactorio, Liquibase ejecuta `update` una vez y termina con el resultado de la migración. Liquibase se conecta internamente a `postgres:5433`; desde el equipo local PostgreSQL está disponible en `127.0.0.1:5434`.

## Liquibase

Si ya existía el volumen antes de hu-db-006, reconcilie primero los roles técnicos desde `.env`; este paso no imprime las contraseñas ni modifica changelogs.

```powershell
.\scripts\reconcile-technical-roles.ps1
```

```powershell
# Valida archivos y referencias sin aplicar cambios.
docker compose run --rm liquibase validate

# Ejecuta manualmente los changesets pendientes.
docker compose run --rm liquibase update

# Muestra el estado detallado.
docker compose run --rm liquibase status --verbose
```

## Verificación y detención

```powershell
# Salud, usuario de aplicación, UTF-8, UTC y persistencia.
.\scripts\verify-postgres.ps1

# Estado y registros.
docker compose ps
docker compose logs postgres

# Matriz de roles: migrator/owner, app sin DDL y PUBLIC sin CREATE.
.\scripts\verify-technical-roles.ps1

# Detiene contenedores y conserva el volumen.
docker compose down
```

Para reiniciar deliberadamente la base local, use `docker compose down --volumes`; elimina sus datos y no se puede deshacer.

## Validación de releases

Antes de integrar una release, ejecute el ciclo completo en una base efímera:

```powershell
.\scripts\test-release.ps1 -ReleaseTag alertamujer-db-v0.12.0
```

El script crea un proyecto Compose, contenedor, red y volumen con nombres únicos; no reutiliza la base local ni publica un puerto fijo. Ejecuta `validate`, `status`, `update-sql`, `update`, las verificaciones de aceptación de las HUs implementadas, `history`, `rollback-count-sql`, `rollback-count`, `updateTestingRollback`, el tag de release y un segundo `update`. Además comprueba que el tag exista exactamente una vez, que el esquema sea idéntico tras revertir y reaplicar, y que no queden locks. El entorno efímero se elimina incluso si una fase falla; la salida nativa de Liquibase conserva el changeset o precondición causante. Use `-KeepEnvironment` solo para diagnóstico.

Los changesets ya aplicados son inmutables: una corrección se entrega en un changeset nuevo. Para cambios incompatibles, planifique expandir, migrar y contraer en releases separadas; el tag debe respetar el formato `alertamujer-db-vX.Y.Z`.

## Configuración

`.env` contiene credenciales locales y no se versiona. `liquibase.properties` solo define la configuración reutilizable de Liquibase; Docker Compose entrega las credenciales al ejecutar el contenedor.
