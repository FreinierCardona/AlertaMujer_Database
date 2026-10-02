# AlertaMujer Database

Repositorio de base de datos de AlertaMujer. Proporciona una instancia local, reproducible y persistente de PostgreSQL para el proyecto, junto con la estructura para organizar cambios de base de datos y sus reversiones.

## Estructura

```text
AlertaMujer_Database/
├── 01_ddl/          # Estructuras de base de datos.
├── 02_dml/          # Operaciones de datos.
├── 03_dcl/          # Roles y permisos.
├── 04_tcl/          # Operaciones transaccionales.
├── 05_rollbacks/    # Reversiones.
├── changelog/       # Versionado del esquema.
├── docker/          # Inicialización técnica de PostgreSQL.
├── scripts/         # Inicio y validación local.
├── .env.example     # Plantilla de configuración.
├── .gitignore       # Exclusiones de Git.
├── docker-compose.yml
└── README.md
```

Cada cambio se desarrolla por funcionalidad: incluye solo las estructuras, datos, permisos y rollback que esa funcionalidad necesita.

## Ejecución local

Requisitos: Docker Desktop en ejecución y puerto local `5434` disponible.

Después de clonar el repositorio, cree `.env` desde la plantilla y complete las credenciales locales. Docker Compose carga `.env` automáticamente; sin ese archivo no podrá iniciar PostgreSQL.

```powershell
Copy-Item .env.example .env
# Edite .env y reemplace POSTGRES_PASSWORD y APP_DB_PASSWORD.
docker compose up -d postgres
docker compose ps
```

Al iniciar, PostgreSQL crea o reutiliza el volumen persistente, ejecuta la inicialización técnica solo si la base aún no existe y publica el estado mediante el `healthcheck`.

## Dónde se ejecuta

| Recurso | Valor |
| --- | --- |
| Contenedor Docker | `alertamujer_db` |
| Servicio Compose | `postgres` |
| Base de datos | `alertamujer_db` |
| Dirección desde el equipo local | `127.0.0.1:5434` |
| Puerto dentro del contenedor | `5433` |
| Volumen persistente | `alertamujer_db_data` |
| Red Docker | `alertamujer_db_network` |

El puerto se publica solo en `127.0.0.1`; no queda expuesto a otros equipos de la red. Desde otro contenedor conectado a `alertamujer_db_network`, PostgreSQL está disponible en `postgres:5433`.

## Validación y operación

```powershell
# Verifica salud, usuario de aplicación, UTF-8, UTC y persistencia.
.\scripts\verify-postgres.ps1

# Confirma que el puerto local responde.
Test-NetConnection 127.0.0.1 -Port 5434

# Consulta los registros del servicio.
docker compose logs postgres

# Detiene el contenedor y conserva los datos del volumen.
docker compose down
```

Para eliminar deliberadamente la base local y sus datos, ejecute `docker compose down --volumes`. Esta operación no se puede deshacer sin una copia de respaldo.

## Seguridad y alcance

`.env.example` es una plantilla sin credenciales reales. `.env` contiene credenciales locales, está excluido de Git y no se debe publicar ni compartir. El repositorio no incluye datos reales, backend ni servicios externos; se limita a la plataforma PostgreSQL local y a la organización del trabajo de base de datos.
