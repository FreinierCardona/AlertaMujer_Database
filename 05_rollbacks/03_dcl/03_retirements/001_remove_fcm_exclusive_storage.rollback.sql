-- Reversión exclusivamente estructural. No se restauran las filas históricas FCM eliminadas por HU-DB-027.
CREATE SCHEMA notification AUTHORIZATION alertamujer_owner;
REVOKE ALL ON SCHEMA notification FROM PUBLIC;
GRANT USAGE ON SCHEMA notification TO alertamujer_app;

ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA notification
  GRANT SELECT, INSERT, UPDATE ON TABLES TO alertamujer_app;
ALTER DEFAULT PRIVILEGES FOR ROLE alertamujer_owner IN SCHEMA notification
  GRANT USAGE, SELECT ON SEQUENCES TO alertamujer_app;

CREATE TABLE notification.user_device_tokens (
  device_token_id UUID        NOT NULL DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL,
  fcm_token       TEXT        NOT NULL,
  platform        VARCHAR(7)  NOT NULL,
  device_label    TEXT,
  is_active       BOOLEAN     NOT NULL,
  last_seen_at    TIMESTAMPTZ,
  invalidated_at  TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_user_device_tokens PRIMARY KEY (device_token_id),
  CONSTRAINT uq_user_device_tokens_fcm_token UNIQUE (fcm_token),
  CONSTRAINT uq_user_device_tokens_id_user UNIQUE (device_token_id, user_id),
  CONSTRAINT fk_user_device_tokens_user FOREIGN KEY (user_id) REFERENCES identity.users (user_id) ON DELETE CASCADE,
  CONSTRAINT ck_user_device_tokens_fcm_token_not_blank CHECK (btrim(fcm_token) <> ''),
  CONSTRAINT ck_user_device_tokens_platform CHECK (platform = 'ANDROID'),
  CONSTRAINT ck_user_device_tokens_invalidation_state CHECK ((is_active AND invalidated_at IS NULL) OR (NOT is_active AND invalidated_at IS NOT NULL)),
  CONSTRAINT ck_user_device_tokens_updated_after_created CHECK (updated_at >= created_at)
);

CREATE TABLE notification.emergency_notification_attempts (
  notification_attempt_id UUID        NOT NULL DEFAULT gen_random_uuid(),
  emergency_id            UUID        NOT NULL,
  contact_user_id         UUID        NOT NULL,
  device_token_id         UUID,
  result_status           VARCHAR(13) NOT NULL DEFAULT 'PENDING',
  provider_message_id     TEXT,
  error_code              TEXT,
  attempted_at            TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT pk_emergency_notification_attempts PRIMARY KEY (notification_attempt_id),
  CONSTRAINT uq_emergency_notification_attempts_emergency_contact UNIQUE (emergency_id, contact_user_id),
  CONSTRAINT fk_emergency_notification_attempts_emergency FOREIGN KEY (emergency_id) REFERENCES emergency.emergencies (emergency_id) ON DELETE CASCADE,
  CONSTRAINT fk_emergency_notification_attempts_contact_user FOREIGN KEY (contact_user_id) REFERENCES identity.users (user_id) ON DELETE CASCADE,
  CONSTRAINT fk_emergency_notification_attempts_device_token_contact FOREIGN KEY (device_token_id, contact_user_id) REFERENCES notification.user_device_tokens (device_token_id, user_id) ON DELETE CASCADE,
  CONSTRAINT ck_emergency_notification_attempts_result_status CHECK (result_status IN ('PENDING', 'SENT_TO_FCM', 'FAILED', 'INVALID_TOKEN', 'NO_TOKEN')),
  CONSTRAINT ck_emergency_notification_attempts_token_result_coherence CHECK ((result_status = 'NO_TOKEN' AND device_token_id IS NULL) OR (result_status <> 'NO_TOKEN' AND device_token_id IS NOT NULL)),
  CONSTRAINT ck_emergency_notification_attempts_updated_after_attempted CHECK (updated_at >= attempted_at)
);

CREATE INDEX ix_user_device_tokens_active_recent ON notification.user_device_tokens (user_id, last_seen_at DESC NULLS LAST) WHERE is_active;
CREATE INDEX ix_emergency_notification_attempts_contact_attempted_at ON notification.emergency_notification_attempts (contact_user_id, attempted_at DESC);

REVOKE ALL ON TABLE notification.user_device_tokens FROM alertamujer_app;
GRANT SELECT, INSERT, UPDATE ON TABLE notification.user_device_tokens TO alertamujer_app;
REVOKE ALL ON TABLE notification.emergency_notification_attempts FROM alertamujer_app;
GRANT SELECT, INSERT, UPDATE ON TABLE notification.emergency_notification_attempts TO alertamujer_app;
