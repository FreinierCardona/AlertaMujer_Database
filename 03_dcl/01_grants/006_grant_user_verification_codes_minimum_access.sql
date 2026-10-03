REVOKE ALL ON TABLE identity.user_verification_codes FROM alertamujer_app;

GRANT INSERT, UPDATE ON TABLE identity.user_verification_codes TO alertamujer_app;

GRANT SELECT (
  verification_code_id,
  user_id,
  registration_request_id,
  channel,
  purpose,
  destination_snapshot,
  expires_at,
  used_at,
  invalidated_at,
  attempt_count,
  max_attempts,
  resend_number,
  created_at,
  updated_at
) ON TABLE identity.user_verification_codes TO alertamujer_app;
