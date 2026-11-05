ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA configuration, identity, profile, contacts, emergency, notification, audit
  REVOKE USAGE, SELECT ON SEQUENCES FROM alertamujer_app;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA audit
  REVOKE SELECT, INSERT ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA notification
  REVOKE SELECT, INSERT, UPDATE ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA emergency
  REVOKE SELECT, INSERT ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA contacts
  REVOKE SELECT, INSERT, UPDATE ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA profile
  REVOKE SELECT, INSERT, UPDATE ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA identity
  REVOKE SELECT, INSERT, UPDATE ON TABLES FROM alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA configuration
  REVOKE SELECT ON TABLES FROM alertamujer_app;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
REVOKE USAGE ON SCHEMA configuration, identity, profile, contacts, emergency, notification, audit FROM alertamujer_app;
GRANT CREATE ON SCHEMA public TO PUBLIC;
