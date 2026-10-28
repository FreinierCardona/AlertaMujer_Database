-- Facilita consultar o revocar las sesiones de una cuenta.
CREATE INDEX ix_user_sessions_user_id
  ON identity.user_sessions (user_id);

-- Facilita localizar sesiones que han caducado.
CREATE INDEX ix_user_sessions_expires_at
  ON identity.user_sessions (expires_at);
