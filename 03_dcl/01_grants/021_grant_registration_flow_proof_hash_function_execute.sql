REVOKE ALL ON FUNCTION identity.get_registration_flow_proof_hash(UUID) FROM alertamujer_app;
GRANT EXECUTE ON FUNCTION identity.get_registration_flow_proof_hash(UUID) TO alertamujer_app;
GRANT SELECT (flow_version, registration_stage)
  ON TABLE identity.registration_requests TO alertamujer_app;
