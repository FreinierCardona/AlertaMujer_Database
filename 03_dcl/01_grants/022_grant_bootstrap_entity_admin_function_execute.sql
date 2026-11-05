REVOKE ALL ON FUNCTION identity.bootstrap_entity_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION identity.bootstrap_entity_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM alertamujer_app;

GRANT EXECUTE ON FUNCTION identity.bootstrap_entity_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO alertamujer_app;
