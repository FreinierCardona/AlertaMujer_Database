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

  CONSTRAINT pk_user_device_tokens
    PRIMARY KEY (device_token_id),

  CONSTRAINT uq_user_device_tokens_fcm_token
    UNIQUE (fcm_token),

  CONSTRAINT uq_user_device_tokens_id_user
    UNIQUE (device_token_id, user_id),

  CONSTRAINT fk_user_device_tokens_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_user_device_tokens_fcm_token_not_blank
    CHECK (btrim(fcm_token) <> ''),

  CONSTRAINT ck_user_device_tokens_platform
    CHECK (platform = 'ANDROID'),

  CONSTRAINT ck_user_device_tokens_invalidation_state
    CHECK (
      (is_active AND invalidated_at IS NULL)
      OR (NOT is_active AND invalidated_at IS NOT NULL)
    ),

  CONSTRAINT ck_user_device_tokens_updated_after_created
    CHECK (updated_at >= created_at)
);
