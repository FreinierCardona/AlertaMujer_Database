-- Expone el hash de continuidad del registro sin permitir leer directamente la columna protegida.
CREATE FUNCTION identity.get_registration_flow_proof_hash(p_registration_request_id UUID)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, identity
AS 'SELECT flow_secret_hash FROM identity.registration_requests WHERE registration_request_id = $1';

-- La ejecución requiere un permiso explícito posterior; no queda abierta a PUBLIC.
REVOKE ALL ON FUNCTION identity.get_registration_flow_proof_hash(UUID) FROM PUBLIC;
