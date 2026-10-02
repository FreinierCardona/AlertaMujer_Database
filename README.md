# AlertaMujer Database

Repositorio de PostgreSQL y Liquibase de AlertaMujer. Centraliza la infraestructura local y el versionamiento ordenado de futuros cambios de base de datos; no contiene datos reales ni changesets de negocio iniciales.

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

Los changelogs internos son el lugar exclusivo para registrar changesets, respetando el orden DDL, DML, DCL y TCL. La hu-db-004 habilita únicamente `citext` en el schema predeterminado de PostgreSQL, sin crear un schema de extensiones; las futuras PK funcionales usarán `uuid NOT NULL DEFAULT gen_random_uuid()`, sin habilitar `pgcrypto`, `uuid-ossp` ni UUIDv7.

## Inicio local

Requiere Docker Desktop y el puerto `5434` disponible.

```powershell
Copy-Item .env.example .env
# Edite .env y defina POSTGRES_PASSWORD y APP_DB_PASSWORD.

# PostgreSQL y Liquibase; Liquibase aplica los changesets pendientes.
docker compose up

# La misma operación en segundo plano.
docker compose up -d
```

PostgreSQL inicia primero. Cuando su `healthcheck` es satisfactorio, Liquibase ejecuta `update` una vez y termina con el resultado de la migración. Liquibase se conecta internamente a `postgres:5433`; desde el equipo local PostgreSQL está disponible en `127.0.0.1:5434`.

## Liquibase

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

# Detiene contenedores y conserva el volumen.
docker compose down
```

Para reiniciar deliberadamente la base local, use `docker compose down --volumes`; elimina sus datos y no se puede deshacer.

## Configuración

`.env` contiene credenciales locales y no se versiona. `liquibase.properties` solo define la configuración reutilizable de Liquibase; Docker Compose entrega las credenciales al ejecutar el contenedor.
