INSERT INTO configuration.system_configuration (
  configuration_id,
  default_sos_message,
  heartbeat_interval_seconds,
  offline_timeout_seconds,
  max_evidence_count,
  max_evidence_size_bytes,
  max_chat_message_length,
  otp_ttl_minutes,
  otp_max_attempts,
  otp_max_resends,
  otp_resend_cooldown_minutes
)
VALUES (
  1,
  'Necesito ayuda. Estoy en una emergencia.',
  60,
  180,
  10,
  1048576,
  500,
  180,
  5,
  3,
  300
)
ON CONFLICT (configuration_id) DO NOTHING;
