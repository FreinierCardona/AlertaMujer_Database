-- Garantiza como máximo una emergencia sin finalizar por usuario, incluso si está OFFLINE.
CREATE UNIQUE INDEX ux_emergencies_open_user
  ON emergency.emergencies (user_id)
  WHERE status <> 'FINALIZED';

-- Facilita consultar el historial del usuario desde la emergencia más reciente.
CREATE INDEX ix_emergencies_user_id_started_at
  ON emergency.emergencies (user_id, started_at DESC);
