REVOKE ALL ON TABLE identity.user_credentials FROM alertamujer_app;

GRANT INSERT, UPDATE ON TABLE identity.user_credentials TO alertamujer_app;

GRANT SELECT (
  credential_id,
  user_id,
  password_updated_at,
  created_at,
  updated_at
) ON TABLE identity.user_credentials TO alertamujer_app;
