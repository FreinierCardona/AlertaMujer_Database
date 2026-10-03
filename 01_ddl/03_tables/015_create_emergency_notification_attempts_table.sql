CREATE TABLE notification.emergency_notification_attempts (
  -- Identity and associations
  notification_attempt_id UUID        NOT NULL DEFAULT gen_random_uuid(),
  emergency_id            UUID        NOT NULL,
  contact_user_id         UUID        NOT NULL,
  device_token_id         UUID,

  -- Provider result
  result_status           VARCHAR(13) NOT NULL DEFAULT 'PENDING',
  provider_message_id     TEXT,
  error_code              TEXT,

  -- Traceability timestamps
  attempted_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_emergency_notification_attempts
    PRIMARY KEY (notification_attempt_id),

  CONSTRAINT uq_emergency_notification_attempts_emergency_contact
    UNIQUE (emergency_id, contact_user_id),

  CONSTRAINT fk_emergency_notification_attempts_emergency
    FOREIGN KEY (emergency_id)
    REFERENCES emergency.emergencies (emergency_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_emergency_notification_attempts_contact_user
    FOREIGN KEY (contact_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_emergency_notification_attempts_device_token_contact
    FOREIGN KEY (device_token_id, contact_user_id)
    REFERENCES notification.user_device_tokens (device_token_id, user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_notification_attempts_result_status
    CHECK (result_status IN ('PENDING', 'SENT_TO_FCM', 'FAILED', 'INVALID_TOKEN', 'NO_TOKEN')),

  CONSTRAINT ck_emergency_notification_attempts_token_result_coherence
    CHECK (
      (result_status = 'NO_TOKEN' AND device_token_id IS NULL)
      OR (result_status <> 'NO_TOKEN' AND device_token_id IS NOT NULL)
    ),

  CONSTRAINT ck_emergency_notification_attempts_updated_after_attempted
    CHECK (updated_at >= attempted_at)
);
