CREATE FUNCTION identity.get_user_session_refresh_token_hash(p_session_id UUID)
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, identity
AS 'SELECT refresh_token_hash FROM identity.user_sessions WHERE session_id = $1';

REVOKE ALL ON FUNCTION identity.get_user_session_refresh_token_hash(UUID) FROM PUBLIC;
