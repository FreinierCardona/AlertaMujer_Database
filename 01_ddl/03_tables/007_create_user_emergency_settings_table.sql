-- Guarda el mensaje SOS personalizado, con una sola preferencia por usuario.
CREATE TABLE profile.user_emergency_settings (

  -- Identidad de la preferencia y vínculo con su cuenta.
  setting_id                 UUID          NOT NULL DEFAULT gen_random_uuid(),
  user_id                    UUID          NOT NULL,

  -- NULL permite usar el mensaje por defecto; un texto presente no puede estar vacío.
  default_emergency_message  VARCHAR(500),

  -- Fechas de creación y última modificación.
  created_at                 TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,

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
