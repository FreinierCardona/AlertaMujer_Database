CREATE UNIQUE INDEX ux_emergencies_open_user
  ON emergency.emergencies (user_id)
  WHERE status <> 'FINALIZED';

CREATE INDEX ix_emergencies_user_id_started_at
  ON emergency.emergencies (user_id, started_at DESC);
