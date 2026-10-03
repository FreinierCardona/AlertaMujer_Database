REVOKE ALL ON TABLE identity.registration_requests FROM alertamujer_app;

GRANT INSERT, UPDATE ON TABLE identity.registration_requests TO alertamujer_app;

GRANT SELECT (
  registration_request_id,
  username,
  first_names,
  last_names,
  email,
  phone,
  status,
  expires_at,
  created_at,
  updated_at
) ON TABLE identity.registration_requests TO alertamujer_app;
