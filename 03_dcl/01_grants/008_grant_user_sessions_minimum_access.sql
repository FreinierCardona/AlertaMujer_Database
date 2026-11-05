REVOKE ALL ON TABLE identity.user_sessions FROM alertamujer_app;

GRANT INSERT, UPDATE ON TABLE identity.user_sessions TO alertamujer_app;

GRANT SELECT (
  session_id,
  user_id,
  client_type,
  device_label,
  last_used_at,
  expires_at,
  revoked_at,
  created_at
) ON TABLE identity.user_sessions TO alertamujer_app;
