-- Facilita buscar códigos asociados a una cuenta.
CREATE INDEX ix_user_verification_codes_user_id
  ON identity.user_verification_codes (user_id);

-- Facilita buscar códigos durante un registro todavía no completado.
CREATE INDEX ix_user_verification_codes_registration_request_id
  ON identity.user_verification_codes (registration_request_id);

-- Facilita localizar códigos vencidos para su depuración.
CREATE INDEX ix_user_verification_codes_expires_at
  ON identity.user_verification_codes (expires_at);
