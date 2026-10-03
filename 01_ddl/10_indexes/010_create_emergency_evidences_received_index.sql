CREATE INDEX ix_emergency_evidences_emergency_received_at
  ON emergency.emergency_evidences (emergency_id, received_at DESC);
