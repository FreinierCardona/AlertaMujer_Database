REVOKE CREATE ON SCHEMA public FROM PUBLIC;

REVOKE ALL ON SCHEMA configuration, identity, profile, contacts, emergency, notification, audit FROM PUBLIC;
GRANT USAGE ON SCHEMA configuration, identity, profile, contacts, emergency, notification, audit TO alertamujer_app;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA configuration
  GRANT SELECT ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA identity
  GRANT SELECT, INSERT, UPDATE ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA profile
  GRANT SELECT, INSERT, UPDATE ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA contacts
  GRANT SELECT, INSERT, UPDATE ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA emergency
  GRANT SELECT, INSERT ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA notification
  GRANT SELECT, INSERT, UPDATE ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA audit
  GRANT SELECT, INSERT ON TABLES TO alertamujer_app;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA configuration, identity, profile, contacts, emergency, notification, audit
  GRANT USAGE, SELECT ON SEQUENCES TO alertamujer_app;
