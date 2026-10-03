CREATE FUNCTION identity.get_user_password_hash(p_user_id UUID)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, identity
AS 'SELECT password_hash FROM identity.user_credentials WHERE user_id = $1';

CREATE FUNCTION identity.get_registration_password_hash(p_registration_request_id UUID)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, identity
AS 'SELECT password_hash FROM identity.registration_requests WHERE registration_request_id = $1';

CREATE FUNCTION identity.get_verification_code_hash(p_verification_code_id UUID)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, identity
AS 'SELECT code_hash FROM identity.user_verification_codes WHERE verification_code_id = $1';

REVOKE ALL ON FUNCTION identity.get_user_password_hash(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION identity.get_registration_password_hash(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION identity.get_verification_code_hash(UUID) FROM PUBLIC;
