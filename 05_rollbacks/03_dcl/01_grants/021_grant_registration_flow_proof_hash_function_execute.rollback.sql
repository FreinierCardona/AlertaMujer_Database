REVOKE EXECUTE ON FUNCTION identity.get_registration_flow_proof_hash(UUID) FROM alertamujer_app;
REVOKE SELECT (flow_version, registration_stage)
  ON TABLE identity.registration_requests FROM alertamujer_app;
