CREATE TABLE profile.user_emergency_settings (
  setting_id                UUID         NOT NULL DEFAULT gen_random_uuid(),
  user_id                   UUID         NOT NULL,
  default_emergency_message VARCHAR(500),
  created_at                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_user_emergency_settings
    PRIMARY KEY (setting_id),

  CONSTRAINT fk_user_emergency_settings_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT uq_user_emergency_settings_user
    UNIQUE (user_id),

  CONSTRAINT ck_user_emergency_settings_message_not_blank
    CHECK (
      default_emergency_message IS NULL
      OR btrim(default_emergency_message) <> ''
    ),

  CONSTRAINT ck_user_emergency_settings_updated_after_created
    CHECK (updated_at >= created_at)
);
