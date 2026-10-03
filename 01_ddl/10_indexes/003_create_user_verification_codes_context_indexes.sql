CREATE INDEX ix_user_verification_codes_user_id
  ON identity.user_verification_codes (user_id);

CREATE INDEX ix_user_verification_codes_registration_request_id
  ON identity.user_verification_codes (registration_request_id);

CREATE INDEX ix_user_verification_codes_expires_at
  ON identity.user_verification_codes (expires_at);
