CREATE TABLE identity.user_verification_codes (
  verification_code_id     UUID         NOT NULL DEFAULT gen_random_uuid(),
  user_id                  UUID,
  registration_request_id  UUID,
  channel                  VARCHAR(5)   NOT NULL,
  purpose                  VARCHAR(22)  NOT NULL,
  destination_snapshot     VARCHAR(255) NOT NULL,
  code_hash                VARCHAR(255) NOT NULL,
  expires_at               TIMESTAMPTZ  NOT NULL,
  used_at                  TIMESTAMPTZ,
  invalidated_at           TIMESTAMPTZ,
  attempt_count            INTEGER      NOT NULL DEFAULT 0,
  max_attempts             INTEGER      NOT NULL DEFAULT 5,
  resend_number            INTEGER      NOT NULL DEFAULT 0,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_user_verification_codes
    PRIMARY KEY (verification_code_id),

  CONSTRAINT fk_user_verification_codes_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_user_verification_codes_registration_request
    FOREIGN KEY (registration_request_id)
    REFERENCES identity.registration_requests (registration_request_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_user_verification_codes_context_xor
    CHECK ((user_id IS NOT NULL) <> (registration_request_id IS NOT NULL)),

  CONSTRAINT ck_user_verification_codes_channel
    CHECK (channel IN ('EMAIL', 'SMS')),

  CONSTRAINT ck_user_verification_codes_purpose
    CHECK (purpose IN (
      'PASSWORD_RESET',
      'PHONE_VERIFICATION',
      'EMAIL_VERIFICATION',
      'PROFILE_CONTACT_CHANGE'
    )),

  CONSTRAINT ck_user_verification_codes_destination_not_blank
    CHECK (btrim(destination_snapshot) <> ''),

  CONSTRAINT ck_user_verification_codes_hash_not_blank
    CHECK (btrim(code_hash) <> ''),

  CONSTRAINT ck_user_verification_codes_expires_after_created
    CHECK (expires_at > created_at),

  CONSTRAINT ck_user_verification_codes_attempt_count
    CHECK (attempt_count BETWEEN 0 AND max_attempts),

  CONSTRAINT ck_user_verification_codes_max_attempts
    CHECK (max_attempts = 5),

  CONSTRAINT ck_user_verification_codes_resend_number
    CHECK (resend_number BETWEEN 0 AND 3),

  CONSTRAINT ck_user_verification_codes_updated_after_created
    CHECK (updated_at >= created_at)
);
