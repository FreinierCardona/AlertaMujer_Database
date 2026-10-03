REVOKE ALL ON FUNCTION identity.get_user_password_hash(UUID) FROM alertamujer_app;
REVOKE ALL ON FUNCTION identity.get_registration_password_hash(UUID) FROM alertamujer_app;
REVOKE ALL ON FUNCTION identity.get_verification_code_hash(UUID) FROM alertamujer_app;
REVOKE ALL ON FUNCTION identity.get_user_session_refresh_token_hash(UUID) FROM alertamujer_app;

GRANT EXECUTE ON FUNCTION identity.get_user_password_hash(UUID) TO alertamujer_app;
GRANT EXECUTE ON FUNCTION identity.get_registration_password_hash(UUID) TO alertamujer_app;
GRANT EXECUTE ON FUNCTION identity.get_verification_code_hash(UUID) TO alertamujer_app;
GRANT EXECUTE ON FUNCTION identity.get_user_session_refresh_token_hash(UUID) TO alertamujer_app;
