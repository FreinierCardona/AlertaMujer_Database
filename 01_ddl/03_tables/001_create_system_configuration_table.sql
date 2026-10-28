-- Agrupa la configuración operativa en una única fila compartida por los módulos.
CREATE TABLE configuration.system_configuration (


  -- Identificador fijo de la configuración; la restricción inferior solo admite el valor 1.
  configuration_id             SMALLINT      PRIMARY KEY,

  -- Parámetros para alertas, conectividad y contenido adjunto.
  default_sos_message          VARCHAR(500)  NOT NULL,
  heartbeat_interval_seconds   SMALLINT      NOT NULL,
  offline_timeout_seconds      SMALLINT      NOT NULL,
  max_evidence_count           SMALLINT      NOT NULL,
  max_evidence_size_bytes      INTEGER       NOT NULL,
  max_chat_message_length      SMALLINT      NOT NULL,

  -- Vigencia, intentos y reenvíos de códigos de verificación.
  otp_ttl_minutes              SMALLINT      NOT NULL,
  otp_max_attempts             SMALLINT      NOT NULL,
  otp_max_resends              SMALLINT      NOT NULL,
  otp_resend_cooldown_minutes  SMALLINT      NOT NULL,

  -- Fechas de creación y última modificación.
  created_at                   TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                   TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_system_configuration_singleton
    CHECK (configuration_id = 1),

  CONSTRAINT ck_system_configuration_default_sos_message_not_blank
    CHECK (btrim(default_sos_message) <> ''),

  CONSTRAINT ck_system_configuration_heartbeat_interval_positive
    CHECK (heartbeat_interval_seconds > 0),

  CONSTRAINT ck_system_configuration_offline_timeout_exceeds_heartbeat
    CHECK (offline_timeout_seconds > heartbeat_interval_seconds),

  CONSTRAINT ck_system_configuration_max_evidence_count_positive
    CHECK (max_evidence_count > 0),

  CONSTRAINT ck_system_configuration_max_evidence_size_positive
    CHECK (max_evidence_size_bytes > 0),

  CONSTRAINT ck_system_configuration_max_chat_message_length_positive
    CHECK (max_chat_message_length > 0),

  CONSTRAINT ck_system_configuration_otp_ttl_positive
    CHECK (otp_ttl_minutes > 0),

  CONSTRAINT ck_system_configuration_otp_max_attempts_positive
    CHECK (otp_max_attempts > 0),

  CONSTRAINT ck_system_configuration_otp_max_resends_positive
    CHECK (otp_max_resends > 0),

  CONSTRAINT ck_system_configuration_otp_resend_cooldown_positive
    CHECK (otp_resend_cooldown_minutes > 0)
);
