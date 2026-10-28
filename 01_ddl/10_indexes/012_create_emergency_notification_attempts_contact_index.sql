-- Facilita consultar intentos históricos de notificación por contacto y fecha.
CREATE INDEX ix_emergency_notification_attempts_contact_attempted_at
  ON notification.emergency_notification_attempts (contact_user_id, attempted_at DESC);
